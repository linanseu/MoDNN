#include "data_loader.h"

DataLoader::DataLoader(Dataset* dataset, unsigned batch_size) {
    batch_size_ = batch_size;
    index_ = 0;
    max_index_ = dataset->getDatasetSize();
    dataset_ = dataset;
}

unsigned DataLoader::getBatchSize() {
    return batch_size_;
}

// TODO : VMM integration
unsigned DataLoader::get_next_batch(float* data, float* labels) {
    unsigned end = (index_+batch_size_ < max_index_) ? (index_+batch_size_) : (max_index_);
    dataset_->get_item_range(index_, end, data, labels);
    index_ += end-index_; 
    return end-index_;
}