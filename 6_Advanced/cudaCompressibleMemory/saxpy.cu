/*
 * Copyright 1993-2020 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

//
// This sample uses the compressible memory allocation if device supports it
// and performs saxpy on it. 
// Compressible memory may give better performance if the data is amenable to 
// compression.

#include <stdio.h>
#include <cuda.h>
#define CUDA_DRIVER_API
#include "helper_cuda.h"
#include "compMalloc.h"

__global__ void saxpy(const float a, const float4 *x, const float4 *y, float4 *z, const size_t n)
{
    for (size_t i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += gridDim.x * blockDim.x)
    {
        const float4 x4 = x[i];
        const float4 y4 = y[i];
        z[i] = make_float4(a * x4.x + y4.x, a * x4.y + y4.y,
                            a * x4.z + y4.z, a * x4.w + y4.w);
    }
}

__global__ void init(float4 *x, float4 *y, float4 *z, const float val, const size_t n)
{
    const float4 val4 = make_float4(val, val, val, val);
    for (size_t i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += gridDim.x * blockDim.x)
    {
        z[i] = x[i] = y[i] = val4;
    }
}

void launchSaxpy(const float a, float4 *x, float4 *y, float4 *z, const size_t n, const float init_val)
{
    cudaEvent_t start, stop;
    float ms;
    int blockSize;
    int minGridSize;

    checkCudaErrors(cudaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, (void*)init));
    dim3 threads = dim3(blockSize, 1, 1);
    dim3 blocks  = dim3(minGridSize, 1, 1);
    init<<<blocks, threads>>>(x, y, z, init_val, n);

    checkCudaErrors(cudaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, (void*)saxpy));
    threads = dim3(blockSize, 1, 1);
    blocks  = dim3(minGridSize, 1, 1);

    checkCudaErrors(cudaEventCreate(&start));
    checkCudaErrors(cudaEventCreate(&stop));
    checkCudaErrors(cudaEventRecord(start));
    saxpy<<<blocks, threads>>>(a, x, y, z, n);
    checkCudaErrors(cudaEventRecord(stop));
    checkCudaErrors(cudaEventSynchronize(stop));
    checkCudaErrors(cudaEventElapsedTime(&ms, start, stop));

    const size_t size = n * sizeof(float4);
    printf("Running saxpy with %d blocks x %d threads = %.3f ms %.3f TB/s\n", blocks.x, threads.x, ms, (size*3)/ms/1e9);
}

int main(int argc, char **argv)
{
    const size_t n = 10485760;

    if (checkCmdLineFlag(argc, (const char **)argv, "help") ||
            checkCmdLineFlag(argc, (const char **)argv, "?")) {
        printf("Usage -device=n (n >= 0 for deviceID)\n");
        exit(EXIT_SUCCESS);
    }

    findCudaDevice(argc, (const char**)argv);
    CUdevice currentDevice;
    checkCudaErrors(cuCtxGetDevice(&currentDevice));

    // Check that the selected device supports virtual memory management
    int vmm_supported = -1;
    checkCudaErrors(cuDeviceGetAttribute(&vmm_supported,
                          CU_DEVICE_ATTRIBUTE_VIRTUAL_ADDRESS_MANAGEMENT_SUPPORTED,
                          currentDevice));
    if (vmm_supported == 0) {
        printf("Device %d doesn't support Virtual Memory Management, waiving the execution.\n", currentDevice);
        exit(EXIT_WAIVED);
    }

    int isCompressionAvailable;
    checkCudaErrors(cuDeviceGetAttribute(&isCompressionAvailable,
                             CU_DEVICE_ATTRIBUTE_GENERIC_COMPRESSION_SUPPORTED,
                             currentDevice));
    if (isCompressionAvailable == 0)
    {
        printf("Device %d doesn't support Generic memory compression, waiving the execution.\n", currentDevice);
        exit(EXIT_WAIVED);
    }

    printf("Generic memory compression support is available\n");

    float4 *x, *y, *z;
    const size_t size = n * sizeof(float4);

    // Allocating compressible memory
    checkCudaErrors(allocateCompressible((void **)&x, size, true));
    checkCudaErrors(allocateCompressible((void **)&y, size, true));
    checkCudaErrors(allocateCompressible((void **)&z, size, true));

    printf("Running saxpy on %zu bytes of Compressible memory\n", size);

    const float a = 1.0f;
    const float init_val = 1.0f;
    launchSaxpy(a, x, y, z, n, init_val);
 
    checkCudaErrors(freeCompressible(x, size, true));
    checkCudaErrors(freeCompressible(y, size, true));
    checkCudaErrors(freeCompressible(z, size, true));

    printf("Running saxpy on %zu bytes of Non-Compressible memory\n", size);
    // Allocating non-compressible memory
    checkCudaErrors(allocateCompressible((void **)&x, size, false));
    checkCudaErrors(allocateCompressible((void **)&y, size, false));
    checkCudaErrors(allocateCompressible((void **)&z, size, false));

    launchSaxpy(a, x, y, z, n, init_val);
 
    checkCudaErrors(freeCompressible(x, size, false));
    checkCudaErrors(freeCompressible(y, size, false));
    checkCudaErrors(freeCompressible(z, size, false));

    printf("\nNOTE: The CUDA Samples are not meant for performance measurements. "
      "Results may vary when GPU Boost is enabled.\n");
    return EXIT_SUCCESS;
}