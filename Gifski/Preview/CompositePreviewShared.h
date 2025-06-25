#pragma once
#ifdef __METAL_VERSION__
// Metal types
#include <metal_stdlib>
using namespace metal;
typedef float2 shared_float2;
typedef float3 shared_float3;
typedef float4 shared_float4;
typedef uint shared_uint;

#define SHARED_CONSTANT constant
#else
// Swift/C types
#include <simd/simd.h>
typedef simd_float2 shared_float2;
typedef simd_float3 shared_float3;
typedef simd_float4 shared_float4;
typedef uint32_t shared_uint;

#define SHARED_CONSTANT
#endif

SHARED_CONSTANT const shared_uint VERTICES_PER_QUAD = 6;
typedef struct {
	/**
	Must be >= 0.
	*/
	shared_float2 videoOrigin;

	/**
	Must be >= 0
	*/
	shared_float2 videoSize;
	shared_float4 firstColor;
	shared_float4 secondColor;

	/**
	Must be >= 1;
	*/
	int gridSize;
} CompositePreviewFragmentUniforms;

typedef struct {
	shared_float2 scale;
} CompositePreviewVertexUniforms;
