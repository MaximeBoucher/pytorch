#include "ATen/ATen.h"
#include "ATen/NativeFunctions.h"
#include "ATen/cuda/CUDATypeConversion.cuh"

#include <THC/THCGeneral.h>
#include <THC/THCThrustAllocator.cuh>
#include <thrust/device_ptr.h>
#include <thrust/sort.h>
#include <thrust/execution_policy.h>
#include <thrust/sequence.h>

#include <algorithm>
#include <sstream>

namespace at {
namespace native {

Tensor& eye_out_cuda(Tensor& result, int64_t n, int64_t m) {
  if (n <= 0) {
    std::ostringstream oss;
    oss << "n must be greater than 0, got: " << n;
    std::runtime_error(oss.str());
  }
  if(m <= 0) {
    m = n;
  }

  result.resize_({n, m});
  result.zero_();

  int64_t sz = std::min<int64_t>(n, m);
  int64_t stride = result.stride(0) + result.stride(1);

  Tensor diag = result.as_strided({sz}, {stride});
  diag.fill_(1);
  return result;
}

Tensor& randperm_out_cuda(Tensor& result, int64_t n, Generator* generator) {
  if (n < 0) {
    std::ostringstream oss;
    oss << "n must be non-negative, got " << n;
    throw std::runtime_error(oss.str());
  }

  AT_CHECK(result.type().scalarTensor(n).defined(),
    "n is too large for result tensor type: '", result.type().toString(), "'");

  result.resize_({n});

  if (result.type().scalarType() == at::ScalarType::Half) {
    auto result_float = CUDA(kFloat).tensor({n});
    result.copy_(randperm_out_cuda(result_float, n, generator));
  } else {
    if (n < 30000) {  // For small inputs, we offload it to CPU instead.
      auto result_cpu = result.type().toBackend(kCPU).tensor({n});
      randperm_out(result_cpu, n, generator);
      result.copy_(result_cpu);
    } else {
      // Generate random values for the keys array
      AT_DISPATCH_ALL_TYPES(
        result.type(), "randperm_out_cuda", [&] {
          using cuda_scalar_t = cuda::into_type<scalar_t>;

          auto keys = result.type().tensor(result.sizes()).random_(generator);

          auto result_data = thrust::device_ptr<cuda_scalar_t>(result.data<cuda_scalar_t>());
          auto keys_data = thrust::device_ptr<cuda_scalar_t>(keys.data<cuda_scalar_t>());

          auto state = globalContext().getTHCState();
          THCThrustAllocator thrustAlloc(state);
          auto policy = thrust::cuda::par(thrustAlloc).on(THCState_getCurrentStream(state));

          thrust::sequence(policy, result_data, result_data + n);

          // Use the sorted order of keys to rearrange the result array
          thrust::sort_by_key(policy, keys_data, keys_data + n, result_data);
        }
      );
    }
  }

  return result;
}

}} // namespace at::native
