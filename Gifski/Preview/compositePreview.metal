#include <metal_stdlib>
#include <metal_graphics>
#include "CompositePreviewShared.h"

using namespace metal;

struct Vertex {
	float2 position;
	float2 texCoords;

	Vertex(float2 position, float2 texCoords): position(position), texCoords(texCoords) {
	}
};

struct VertexOut {
	// The position of the vertex in homogenous clip space. In our case, the clip space goes from -1...1 in both the x and y directions. (-1,-1) is the bottom-left of the screen, while (1,1) is the top right. The position goes from  0...1 in the z direction, and it is used by the depth buffer to decide what pixels will occlude other pixels. In our case pixels "closer" to 0 will be "on-top" of pixels "farther" away (1.0 being the maximium depth). w will be kept 1.0 and can be ignored for now.
	float4 position [[position]];
	// pass the texture coordinates on to the fragment shader. Tex coords range from 0...1 in s and t (ie, horizontal and vertical)
	float2 texCoords;
	// pass wheter or not the triangle is checkeboard to the fragment shader
	uint isCheckerboard;

	VertexOut(Vertex vert, float2 scale, float z, bool isCheckerboard):
	position(float4(vert.position * scale, z, 1.0)),
	texCoords(vert.texCoords),
	isCheckerboard(isCheckerboard)
	{

	}
};


constant int vertexIndices[VERTICES_PER_QUAD] = {0, 1, 2, 2, 1, 3};
constant Vertex vertices[4] = {
	Vertex(float2(-1.0, -1.0), float2(0.0, 0.0)),
	Vertex(float2( 1.0, -1.0), float2(1.0, 0.0)),
	Vertex(float2(-1.0,  1.0), float2(0.0, 1.0)),
	Vertex(float2( 1.0,  1.0), float2(1.0, 1.0))
};



/**
 The vertex shader computes the position of each vertex. This function gets called once per vertex (which in our case is VERTICES_PER_QUAD * 2 vertices). This shader just simply looks up the vertex position, and texcoordinates from some precomputed vertex data I include thei shader. After the vertex shader stage completes, the GPU will [rasterize](https://jtsorlinis.github.io/rendering-tutorial/)  each triangle, computing the position of pixel on the screen. Then it will move on to the fragment shader `previewFragment`.
 */
vertex VertexOut previewVertexShader(uint vertexID [[vertex_id]],
									 constant CompositePreviewVertexUniforms &uniforms [[buffer(0)]]
									 ) {
	bool isCheckerboard = vertexID >= VERTICES_PER_QUAD;
	return VertexOut(
					 vertices[vertexIndices[vertexID % VERTICES_PER_QUAD]],
					 isCheckerboard ? float2(1.0, 1.0) : uniforms.scale,
					 isCheckerboard ? 0.5 : 0.1,
					 isCheckerboard
					 );
}

/**
The preview fragment shader runs for each rasterized pixel . The data from each vertex (`VertexOut`) for each triangle is interpolated (at one of the vertices the data is exactly the same as the input vertex; in the exact middle of the triangle is a blend of each vertex). Returns a color for the pixel.
*/
fragment float4 previewFragment(VertexOut in [[stage_in]],
							   texture2d<float> inputTexture [[texture(0)]],
							   sampler inputSampler [[sampler(0)]],
								constant CompositePreviewFragmentUniforms &uniforms [[buffer(0)]]
								) {
	if (!in.isCheckerboard) {
		// grab the color given by the texture at the coordinates given by texCoords
		return inputTexture.sample(inputSampler, in.texCoords);
	}

	float2 topLeftOriginTexCoords = float2(in.texCoords.x, 1.0 - in.texCoords.y);
	float2 texCoordsInPixels = topLeftOriginTexCoords * uniforms.videoSize + uniforms.videoOrigin;
	int gridSize = uniforms.gridSize;

	int checkerX = (int(texCoordsInPixels.x) % (gridSize*2)) >= gridSize ? 1 : 0;
	int checkerY = (int(texCoordsInPixels.y) % (gridSize*2)) >= gridSize ? 1 : 0;
	return (checkerX + checkerY) % 2 == 0 ? uniforms.firstColor : uniforms.secondColor;
}
