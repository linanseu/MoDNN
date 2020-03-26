#include "layers.h"

namespace layers{
class PoolingLayer : public Layer {
	private:
		cudnnHandle_t* handle_;
		cudnnTensorDescriptor_t input_descriptor;
		cudnnTensorDescriptor_t output_descriptor;
		cudnnPoolingDescriptor_t pooling_descriptor;
		size_t forward_workspace_bytes, backward_workspace_bytes;
	public:
		PoolingLayer(cudnnHandle_t* handle, 
					int window_height, 
					int window_width, 
					int vertical_stride,
					int horizontal_stride,
					int batch_size,
                    int input_height,
                    int input_width,
                    int input_channels,
					padding_type pad, 
					int mode
				);
		void forward(float alpha, float beta, float* d_input, float* d_output);
		void backward(float* d_input, float* d_input_dx, float* d_output, float* d_output_dx);
		int get_output_shape_and_bytes(int shape[]);
	};
}