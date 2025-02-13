StructuredBuffer<unorm float4> ColorBuffer : register(t0, space0);

struct Input
{
	float2 Position : TEXCOORD0;
	uint VertexIndex : SV_VertexID;
};

struct Output
{
	float4 Color : TEXCOORD0;
    float4 Position : SV_Position;
};

Output main(Input input)
{
    Output output;
	output.Color = ColorBuffer[input.VertexIndex / 4];
    output.Position = float4(input.Position, 0.0f, 1.0f);
    return output;
}
