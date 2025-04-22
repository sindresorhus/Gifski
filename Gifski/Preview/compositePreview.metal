//
//  compositePreview.metal
//  Gifski
//
//  Created by Michael Mulet on 4/22/25.
//

#include <metal_stdlib>
#include <metal_graphics>
#include <metal_mesh>
using namespace metal;

struct VertexOut {
	float4 position [[position]];
	float2 texCoords;
	VertexOut(float3 position, float2 texCoords): texCoords(texCoords) {
		this->position = float4(position, 1.0);
	}
};

struct MeshUniforms {
	float2 scale;
};

struct PrimitiveOut {
	/**
	 whether this primitive is for the original frame or the preview frame
	 */
	bool original;
};

/**
 Simply makes two quads, one for the original, one for the preview, both are centered, the preview is scaled to the
 */
[[mesh]]
void previewMeshShader(
				   mesh<VertexOut, PrimitiveOut, 8, 4, topology::triangle> output,
	constant MeshUniforms &uniforms [[buffer(0)]]
) {
	float2 positions[4] = {
		float2(-1.0, -1.0),
		float2( 1.0, -1.0),
		float2(-1.0,  1.0),
		float2( 1.0,  1.0)
	};
	float2 texCoords[4] = {
		float2(0.0, 1.0),
		float2(1.0, 1.0),
		float2(0.0, 0.0),
		float2(1.0, 0.0)
	};
	uint numVerticesInQuad = 4;
	uint numIndicesInQuad = 6;
	for (uint i = 0; i < numVerticesInQuad; ++i) {

		/**
		 original
		 */
		output.set_vertex(i, VertexOut(float3(positions[i], 0.5), texCoords[i] ));


		/**
		 preview
		 */
		output.set_vertex(i + numVerticesInQuad, VertexOut(float3(positions[i] * uniforms.scale, 0.1), texCoords[i] ));
	}

	/**
	 Offsets for the indices and vertices respectively for setting up the index buffer
	 */
	uint2 offsets[2] = {
		/**
		 original
		 */
		uint2(0,0),
		/**
		 preview
		 */
		uint2(numIndicesInQuad,numVerticesInQuad)
	};
	for(uint i = 0; i < 2; ++i){
		uint2 offset = offsets[i];
		output.set_index(0 + offset.x, 0 + offset.y);
		output.set_index(1 + offset.x, 1 + offset.y);
		output.set_index(2 + offset.x, 2 + offset.y);
		output.set_index(3 + offset.x, 2 + offset.y);
		output.set_index(4 + offset.x, 1 + offset.y);
		output.set_index(5 + offset.x, 3 + offset.y);

	}

	output.set_primitive(0, PrimitiveOut{.original = true});
	output.set_primitive(1, PrimitiveOut{.original = true});

	output.set_primitive(2, PrimitiveOut{.original = false});
	output.set_primitive(3, PrimitiveOut{.original = false});

	output.set_primitive_count(4);

}

struct fragmentIn
{
	VertexOut v;
	PrimitiveOut p;
};

struct FragmentUniforms {
	float blurStrength;
};

/**
 If preview it just draws a texture. if the original, it blurs it.
 */
fragment float4 previewFragment(fragmentIn in [[stage_in]],
							   texture2d<float> inputTexture [[texture(0)]],
								texture2d<float> texture2 [[texture(1)]],
							   sampler inputSampler [[sampler(0)]],
								constant FragmentUniforms &uniforms [[buffer(0)]]
								) {
	if (!in.p.original) {
		return inputTexture.sample(inputSampler, in.v.texCoords);
	}

	float blurStrength = uniforms.blurStrength;
	float2 texelSize = blurStrength / float2(texture2.get_width(), texture2.get_height());
	float blurKernel[3][3] = {
		{1.0/16, 2.0/16, 1.0/16},
		{2.0/16, 4.0/16, 2.0/16},
		{1.0/16, 2.0/16, 1.0/16}
	};
	float4 color = float4(0.0);
	for (int x = -1; x <= 1; ++x) {
		for (int y = -1; y <= 1; ++y) {
			float2 offset = float2(x, y) * texelSize;
			color += blurKernel[x+1][y+1] * texture2.sample(inputSampler, in.v.texCoords + offset);
		}
	}
	return color;
}
