#include "trainer.h"

void train_with_minimal_memory(DataLoader * dataloader,Dataset * dataset,seqNetwork * nn, vmm * mem_manager, int epochs)
{
  int dataset_size = dataset->getDatasetSize(),batch_size = nn->batch_size;
  float* data_batch, *label_batch;
  int* label_batch_integer = (int*)malloc(sizeof(int)*batch_size);

  int sub_batch_size = nn->sub_batch_size();
  int offset = ((batch_size/sub_batch_size)-1)*sub_batch_size;
  
  //nn->allocate_all_memory(mem_manager);
  mem_manager->printNodes();
  nn->print_network_info();

  std::cout << "Allocating Params Memory" << std::endl;
  nn->allocate_mem_params(mem_manager);
  mem_manager->printNodes();

  std::cout << "Allocating Input - Output Memory" << std::endl;
  nn->allocate_mem_layer(0,mem_manager);
  mem_manager->printNodes();
  nn->link_layer_buffer(0);

  std::cout << "Allocating FC - Output Memory" << std::endl;
  nn->allocate_mem_layer(2,mem_manager);
  mem_manager->printNodes();
  nn->link_layer_buffer(2);

  std::cout << "Allocating Softmax - Output Memory" << std::endl;
  nn->allocate_mem_layer(3,mem_manager);
  mem_manager->printNodes();
  nn->link_layer_buffer(3);


  // int shape[4];
  // nn->get_output_shape(shape,nn->num_layers-1);
  // std::cout << "Randomising Parameters of the neural network" << std::endl;
  // nn->randomise_params();
  //
  //
  // float * output,loss;
  //
  //
  // int num_iters_in_epoch =  dataset_size/batch_size;
  // bool rem = false;
  //
  //
  // if(dataset_size%batch_size!=0){
  //   num_iters_in_epoch+=1;
  //   rem = true;
  //   }
  // if(rem)
  //   std::cout << "Ignoring last batch " << std::endl;
  //
  // std::cout << "Number of iterations in an epoch " << num_iters_in_epoch << std::endl;
  // for(int j=0;j<epochs;j++)
  // {
  //   loss = 0;
  //   for(int i=0;i<num_iters_in_epoch;i++) //put back num_iters_in_epoch
  //   {
  //     if(rem && i==num_iters_in_epoch-1)
  //       break;
  //
  //     dataloader->get_next_batch(&data_batch, &label_batch);
  //     label_batch_converter_mnist(label_batch, label_batch_integer, batch_size);
  //
  //
  //     nn->update_batch(data_batch, label_batch_integer);
  //     nn->forward();
  //     nn->backward();
  //     nn->update_weights();
  //     if(j%PRINT_EVERY==0)
  //     {
  //       output = nn->offload_buffer(nn->num_layers-1,"output",shape);
  //
  //       loss += categorical_cross_entropy_loss(output,shape,label_batch_integer);
  //     }
  //
  //   }
  //
  //   if(j%PRINT_EVERY==0)
  //   {
  //     loss = loss/(float)(dataset_size);
  //     std::cout << "Epoch number "<<j+1<< " : " << "Loss :- " << loss <<std::endl;
  //   }
  //   dataloader->reset();
  //   dataset->shuffle();
  // }

}