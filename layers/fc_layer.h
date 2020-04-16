#ifndef FC_LAYER_H_
#define FC_LAYER_H_

#include "layers.h"

#define USE_CUBLAS true //DONT SET TO FALSE
#define TILE_SIZE  32
#define BLOCK_SIZE 8


namespace layers{

class FCLayer : public layers::Layer
 {
  public:
    cublasHandle_t handle;
    FCLayer(cublasHandle_t cublas,int batch_size,int input_height,int output_height);
    int get_output_shape_and_bytes(int shape[]);
    void forward(float* d_input, float * d_kernel, float * d_output); //checked with numpy and working correctly
    void backward(float alpha, float beta_weights, float beta_input, float *d_input, float* d_kernel,float *d_diffkernel,float *d_diffinput, float *d_diffoutput,float lr); //checked with numpy for parameter gradient
    int allocate_internal_mem(float **d_kernel,float **d_diffkernel);
    void update_weights(float* d_kernel, float* d_diffkernel, float lr,cudaStream_t compute_stream);
    void populate_filter_params(float *d_kernel);
    int get_input_shape_and_bytes(int shape[]);
    int get_params_shape_and_bytes(int shape[]);
    int get_total_memory();
 };
}

 #endif
