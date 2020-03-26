#include <iostream>
#include "layers.h"
#include <random>

using namespace layers;

std::map<std::string,float*> init_buffer_map()
{
  std::map<std::string,float*> buffer_map;
  buffer_map["input"] = nullptr;
  buffer_map["output"] = nullptr;
  buffer_map["workspace"] = nullptr;
  buffer_map["params"] = nullptr;

  buffer_map["dinput"] = nullptr;
  buffer_map["doutput"] = nullptr;
  buffer_map["dparams"] = nullptr;

  return buffer_map;
}

const char* cublasGetErrorString(cublasStatus_t status)
{
    switch(status)
    {
        case CUBLAS_STATUS_SUCCESS: return "CUBLAS_STATUS_SUCCESS";
        case CUBLAS_STATUS_NOT_INITIALIZED: return "CUBLAS_STATUS_NOT_INITIALIZED";
        case CUBLAS_STATUS_ALLOC_FAILED: return "CUBLAS_STATUS_ALLOC_FAILED";
        case CUBLAS_STATUS_INVALID_VALUE: return "CUBLAS_STATUS_INVALID_VALUE";
        case CUBLAS_STATUS_ARCH_MISMATCH: return "CUBLAS_STATUS_ARCH_MISMATCH";
        case CUBLAS_STATUS_MAPPING_ERROR: return "CUBLAS_STATUS_MAPPING_ERROR";
        case CUBLAS_STATUS_EXECUTION_FAILED: return "CUBLAS_STATUS_EXECUTION_FAILED";
        case CUBLAS_STATUS_INTERNAL_ERROR: return "CUBLAS_STATUS_INTERNAL_ERROR";
    }
    return "unknown error";
}


ConvLayer::ConvLayer(cudnnHandle_t cudnn,
                  int batch_size,
                  int input_height,
                  int input_width,
                  int input_channels,
                  int kernel_height,
                  int kernel_width,
                  int output_channels,
                  padding_type pad
           )
  {
    handle = cudnn;
    ibatch_size = batch_size;
    ichannels = input_channels;
    iheight = input_height;
    iwidth = input_width;
    ikernel_width = kernel_width;
    ikernel_height = kernel_height;

    checkCUDNN(cudnnCreateTensorDescriptor(&input_descriptor));
    checkCUDNN(cudnnSetTensor4dDescriptor(input_descriptor,
                                          /*format=*/CUDNN_TENSOR_NCHW,
                                          /*dataType=*/CUDNN_DATA_FLOAT,
                                          /*batch_size=*/batch_size,
                                          /*channels=*/input_channels,
                                          /*image_height=*/input_height,
                                          /*image_width=*/input_width));
    checkCUDNN(cudnnCreateFilterDescriptor(&kernel_descriptor));

    checkCUDNN(cudnnSetFilter4dDescriptor(kernel_descriptor,
                                          /*dataType=*/CUDNN_DATA_FLOAT,
                                          /*format=*/CUDNN_TENSOR_NCHW,
                                          /*out_channels=*/output_channels,
                                          /*in_channels=*/input_channels,
                                          /*kernel_height=*/kernel_height,
                                          /*kernel_width=*/kernel_width));

    checkCUDNN(cudnnCreateConvolutionDescriptor(&convolution_descriptor));

    if(pad == SAME){
    checkCUDNN(cudnnSetConvolution2dDescriptor(convolution_descriptor,
                                               /*pad_height=*/kernel_height/2,
                                               /*pad_width=*/kernel_width/2,
                                               /*vertical_stride=*/1,
                                               /*horizontal_stride=*/1,
                                               /*dilation_height=*/1,
                                               /*dilation_width=*/1,
                                               /*mode=*/CUDNN_CROSS_CORRELATION,
                                               /*computeType=*/CUDNN_DATA_FLOAT));
   }
   else if(pad == VALID)
   {
     checkCUDNN(cudnnSetConvolution2dDescriptor(convolution_descriptor,
                                                /*pad_height=*/0,
                                                /*pad_width=*/0,
                                                /*vertical_stride=*/1,
                                                /*horizontal_stride=*/1,
                                                /*dilation_height=*/1,
                                                /*dilation_width=*/1,
                                                /*mode=*/CUDNN_CROSS_CORRELATION,
                                                /*computeType=*/CUDNN_DATA_FLOAT));
   }

   obatch_size= 0, ochannels= 0, oheight = 0, owidth = 0;
   checkCUDNN(cudnnGetConvolution2dForwardOutputDim(convolution_descriptor,
                                                    input_descriptor,
                                                    kernel_descriptor,
                                                    &obatch_size,
                                                    &ochannels,
                                                    &oheight,
                                                    &owidth));

   //std::cerr << "Output Image: " << obatch_size << " x "<< oheight << " x " << owidth << " x " << ochannels
  //           << std::endl;



   checkCUDNN(cudnnCreateTensorDescriptor(&output_descriptor));
   checkCUDNN(cudnnSetTensor4dDescriptor(output_descriptor,
                                         /*format=*/CUDNN_TENSOR_NCHW,
                                         /*dataType=*/CUDNN_DATA_FLOAT,
                                         /*batch_size=*/obatch_size,
                                         /*channels=*/ochannels,
                                         /*image_height=*/oheight,
                                         /*image_width=*/owidth));

   checkCUDNN(
       cudnnGetConvolutionForwardAlgorithm(cudnn,
                                           input_descriptor,
                                           kernel_descriptor,
                                           convolution_descriptor,
                                           output_descriptor,
                                           CUDNN_CONVOLUTION_FWD_PREFER_FASTEST,
                                           /*memoryLimitInBytes=*/0,
                                           &convolution_algorithm));

   checkCUDNN(cudnnGetConvolutionForwardWorkspaceSize(cudnn,
                                                      input_descriptor,
                                                      kernel_descriptor,
                                                      convolution_descriptor,
                                                      output_descriptor,
                                                      convolution_algorithm,
                                                      &forward_workspace_bytes));


    //std::cerr << "Forward Workspace Size: " << (forward_workspace_bytes / 1048576.0) << "MB"
    //          << std::endl;



    //Filter Backward Algorithm and Workspace Size

    size_t temp;
    backward_workspace_bytes=0;



    checkCUDNN(cudnnGetConvolutionBackwardFilterAlgorithm(
              handle, input_descriptor, output_descriptor, convolution_descriptor, kernel_descriptor,
              CUDNN_CONVOLUTION_BWD_FILTER_PREFER_FASTEST, 0, &filter_algo));


    checkCUDNN(cudnnGetConvolutionBackwardFilterWorkspaceSize(
              handle, input_descriptor, output_descriptor, convolution_descriptor, kernel_descriptor,
              filter_algo, &temp));



    backward_workspace_bytes = std::max(temp,backward_workspace_bytes);


    //Data Backward Algorithm and workspace size

    checkCUDNN(cudnnGetConvolutionBackwardDataAlgorithm(
              handle, kernel_descriptor, output_descriptor, convolution_descriptor, input_descriptor,
              CUDNN_CONVOLUTION_BWD_DATA_PREFER_FASTEST, 0, &data_algo));

    checkCUDNN(cudnnGetConvolutionBackwardDataWorkspaceSize(
        handle, kernel_descriptor, output_descriptor, convolution_descriptor, input_descriptor,
        data_algo, &temp));

    backward_workspace_bytes = std::max(temp,backward_workspace_bytes);
    //std::cerr << "Backward Workspace Size: " << (backward_workspace_bytes / 1048576.0) << "MB"
    //          << std::endl;
  }


int ConvLayer::get_output_shape_and_bytes(int shape[])
  {
    //Get Output Shape in NHWC format
    shape[0] = obatch_size;
    shape[1] = oheight;
    shape[2] = owidth;
    shape[3] = ochannels;
    return shape[0]*shape[1]*shape[2]*shape[3]*sizeof(float);
  }


void Layer::forward()
{

}

int ConvLayer::get_input_shape_and_bytes(int shape[])
  {
    //Get Output Shape in NHWC format
    shape[0] = ibatch_size;
    shape[1] = iheight;
    shape[2] = iwidth;
    shape[3] = ichannels;
    return shape[0]*shape[1]*shape[2]*shape[3]*sizeof(float);
  }

size_t ConvLayer::get_forward_workspace_bytes()
  {
    return forward_workspace_bytes;
  }

size_t ConvLayer::get_backward_workspace_bytes()
  {
    return backward_workspace_bytes;
  }

size_t ConvLayer::get_total_workspace_size()
  {
    return std::max(forward_workspace_bytes,backward_workspace_bytes);
  }

void ConvLayer::forward(float alpha, float beta, float* d_input, float* d_kernel, void* d_workspace, float * d_output)
  {
    checkCUDNN(cudnnConvolutionForward(handle,
                                       &alpha,
                                       input_descriptor,
                                       d_input,
                                       kernel_descriptor,
                                       d_kernel,
                                       convolution_descriptor,
                                       convolution_algorithm,
                                       d_workspace,
                                       forward_workspace_bytes,
                                       &beta,
                                       output_descriptor,
                                       d_output));
  }

int ConvLayer::allocate_internal_mem(float **d_kernel, void **d_workspace,float **d_diffkernel)
  {
      int param_size = sizeof(float)*ikernel_width*ikernel_height*ichannels*ochannels;
      int workspace_size = get_total_workspace_size();
      cudaMalloc(d_kernel, param_size);
      cudaMalloc(d_workspace,workspace_size);
      cudaMalloc(d_diffkernel,param_size);

      return param_size+workspace_size;

  }

void ConvLayer::populate_filter_params(float *d_kernel)
{
  float init_params[ochannels][ikernel_height][ikernel_width][ichannels];
  std::normal_distribution<float> distribution(MU,SIGMA);
  std::default_random_engine generator;

  for(int ochannel = 0; ochannel < ochannels; ochannel++)
    for(int row=0;row<ikernel_height;row++)
      for(int col=0;col<ikernel_width;col++)
        for(int ichannel=0;ichannel < ichannels; ichannel++)
          init_params[ochannel][row][col][ichannel] = distribution(generator);


  cudaMemcpy(d_kernel,init_params,sizeof(init_params),cudaMemcpyHostToDevice);

}



ConvLayer::~ConvLayer()
{
    cudnnDestroyTensorDescriptor(input_descriptor);
    cudnnDestroyTensorDescriptor(output_descriptor);
    cudnnDestroyFilterDescriptor(kernel_descriptor);
    cudnnDestroyConvolutionDescriptor(convolution_descriptor);
}


InputLayer::InputLayer(int batch_size, int height, int width, int channels,int num_classes)
{
  ibatch_size = obatch_size = batch_size;
  iheight = oheight = height;
  iwidth = owidth = width;
  ichannels = ochannels = channels;
  this->num_classes = num_classes;
}

int InputLayer::get_output_shape_and_bytes(int shape[])
{
    //Get Output Shape in NHWC format
    shape[0] = obatch_size;
    shape[1] = oheight;
    shape[2] = owidth;
    shape[3] = ochannels;
    return shape[0]*shape[1]*shape[2]*shape[3]*sizeof(float);
}



void InputLayer::randomly_populate(float *data,float * labels)
{
  float init_params[obatch_size][oheight][owidth][ochannels];
  int init_labels[obatch_size];
  int class_;
  std::normal_distribution<float> distribution(MU,SIGMA);
  std::default_random_engine generator;

  for(int data_point = 0; data_point < obatch_size; data_point++)
    for(int row=0;row<oheight;row++)
      for(int col=0;col<owidth;col++)
        for(int ochannel=0;ochannel < ochannels; ochannel++){
          init_params[data_point][row][col][ochannel] = distribution(generator);
        }

  //std::cout << "Checking random input layer" << std::endl;
  //std::cout << init_params[0][0][0][1] << std::endl;
  cudaMemcpy(data,init_params,sizeof(init_params),cudaMemcpyHostToDevice);

  for (int j = 0; j < obatch_size; j++)
  {
    class_ = rand() % num_classes;
    init_labels[j] = class_;

  }

  cudaMemcpy((void *)(labels),init_labels,sizeof(init_labels),cudaMemcpyHostToDevice);

}


Flatten::Flatten(int batch_size,int input_height,int input_width,int input_channels)
{
  ibatch_size = batch_size;
  ichannels = input_channels;
  iheight = input_height;
  iwidth = input_width;
  obatch_size = batch_size;
  oheight = input_channels*input_height*input_width;

}

int Flatten::get_output_shape_and_bytes(int shape[])
{
  shape[0] = obatch_size;
  shape[1] = oheight;
  shape[2] = -1;
  shape[3] = -1;

  return obatch_size*oheight*sizeof(float);
}

int Flatten::get_input_shape_and_bytes(int shape[])
{
  shape[0] = ibatch_size;
  shape[1] = iheight;
  shape[2] = iwidth;
  shape[3] = ichannels;

  return obatch_size*oheight*sizeof(float);
}

FCLayer::FCLayer(cublasHandle_t cublas,int batch_size, int input_height, int output_height)
{
  handle = cublas;
  ibatch_size = batch_size;
  iheight = input_height;
  obatch_size = ibatch_size;
  oheight = output_height;
}

int FCLayer::get_output_shape_and_bytes(int shape[])
{
  shape[0] = obatch_size;
  shape[1] = oheight;
  shape[2] = -1;
  shape[3] = -1;

  return obatch_size*oheight*sizeof(float);
}

int FCLayer::get_input_shape_and_bytes(int shape[])
{
  shape[0] = obatch_size;
  shape[1] = iheight;
  shape[2] = -1;
  shape[3] = -1;

  return obatch_size*oheight*sizeof(float);
}

int FCLayer::get_params_shape_and_bytes(int shape[])
{
  shape[0] = iheight;
  shape[1] = oheight;
  shape[2] = -1;
  shape[3] = -1;

  return iheight*oheight*sizeof(float);
}

int FCLayer::allocate_internal_mem(float **d_kernel,float **d_diffkernel)
{
  int param_size = iheight*oheight*sizeof(float);
  cudaMalloc(d_kernel,param_size);
  cudaMalloc(d_diffkernel,param_size);
  return param_size;
}

void FCLayer::populate_filter_params(float *d_kernel)
{
  float init_params[iheight][oheight];
  std::normal_distribution<float> distribution(MU,SIGMA);
  std::default_random_engine generator;
  for(int i=0;i<iheight;i++)
    for(int j=0;j<oheight;j++)
      init_params[i][j] = distribution(generator);



  cudaMemcpy(d_kernel,init_params,sizeof(init_params),cudaMemcpyHostToDevice);
}

void FCLayer::forward(float * d_input, float * d_kernel, float * d_output)
{
  float alpha = 1.0,beta = 0.0;
  //we are multiplying d_input(A) * d_kernel(B), both stored in row major form
  //d_input [obatch_sizexiheight] d_okernel[iheight*oheight]
  //in comments A[MxK] B[KxN]
  checkCUBLAS(cublasSgemm(handle,
              CUBLAS_OP_N, //info for B, use CUBLAS_OP_T if you want to use BT
              CUBLAS_OP_N, //info for A, use CUBLAS_OP_T if you want to use AT
              oheight,/*N*/
              obatch_size,/*M*/
              iheight,/*K*/
              &alpha,
              d_kernel, //B
              oheight, //N
              d_input, //A
              iheight, //K
              &beta,
              d_output,//C
              oheight //K
            ));
}

void FCLayer::backward(float *d_input, float* d_kernel,float *d_diffkernel,float *d_diffinput, float *d_diffoutput)
{
  float alpha = 1.0,beta = 0.0;
  checkCUBLAS(cublasSgemm(handle,
              CUBLAS_OP_N, //info for B, use CUBLAS_OP_T if you want to use BT
              CUBLAS_OP_T, //info for A, use CUBLAS_OP_T if you want to use AT
              oheight,/*N*/
              iheight,/*M*/
              obatch_size,/*K*/
              &alpha,
              d_diffoutput, //B
              oheight, //N
              d_input, //A
              iheight, //K
              &beta,
              d_diffkernel,//C
              oheight //K
            ));

  checkCUBLAS(cublasSgemm(handle,
              CUBLAS_OP_T, //info for B, use CUBLAS_OP_T if you want to use BT
              CUBLAS_OP_N, //info for A, use CUBLAS_OP_T if you want to use AT
              iheight,/*N*/
              obatch_size,/*M*/
              oheight,/*K*/
              &alpha,
              d_kernel, //B
              oheight, //N
              d_diffoutput, //A
              oheight, //K
              &beta,
              d_diffinput,//C
              iheight //K
            ));
}



Softmax::Softmax(cudnnHandle_t cudnn,int batch_size,int input_height)
{
  handle = cudnn;
  ibatch_size = obatch_size = batch_size;
  iheight = oheight = input_height;
  checkCUDNN(cudnnCreateTensorDescriptor(&input_descriptor));
  checkCUDNN(cudnnCreateTensorDescriptor(&output_descriptor));
  checkCUDNN(cudnnCreateTensorDescriptor(&diff_descriptor));
  checkCUDNN(cudnnSetTensor4dDescriptorEx(input_descriptor,CUDNN_DATA_FLOAT,obatch_size,oheight,1,1,oheight,1,1,1));
  checkCUDNN(cudnnSetTensor4dDescriptorEx(output_descriptor,CUDNN_DATA_FLOAT,obatch_size,oheight,1,1,oheight,1,1,1));
  checkCUDNN(cudnnSetTensor4dDescriptorEx(diff_descriptor,CUDNN_DATA_FLOAT,obatch_size,oheight,1,1,oheight,1,1,1));

}

int Softmax::get_output_shape_and_bytes(int shape[])
{
  shape[0] = obatch_size;
  shape[1] = oheight;
  shape[2] = -1;
  shape[3] = -1;

  return obatch_size*oheight*sizeof(float);
}

int Softmax::get_input_shape_and_bytes(int shape[])
{
  shape[0] = obatch_size;
  shape[1] = oheight;
  shape[2] = -1;
  shape[3] = -1;

  return obatch_size*oheight*sizeof(float);
}

void Softmax::forward(float* d_input, float * d_output)
{
  float alpha = 1.0;
  float beta = 0.0;
  checkCUDNN(cudnnSoftmaxForward(handle,
                      CUDNN_SOFTMAX_ACCURATE,
                      CUDNN_SOFTMAX_MODE_CHANNEL,
                      &alpha,
                      input_descriptor,
                      d_input,
                      &beta,
                      output_descriptor,
                      d_output));

}


void Softmax::backward(const int *label, float *diff, float * output)
{
  cudaMemcpy(diff,output,obatch_size*oheight*sizeof(float),cudaMemcpyDeviceToDevice);
  SoftmaxLossBackprop<<<(obatch_size+255)/256, 256>>>(label, oheight, obatch_size, diff);
}

int calc_bytes_from_shape(int shape[])
{
  int bytes = 1;
  for(int i=0;i<4;i++)
  {
    if(shape[i]==-1)break;
    else bytes*=shape[i];
  }
  return bytes;
}
