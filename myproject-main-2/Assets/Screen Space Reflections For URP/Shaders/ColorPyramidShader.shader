Shader "Hidden/ColorPyramidShader"
{
    HLSLINCLUDE
    
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        // The Blit.hlsl file provides the vertex shader (Vert),
        // the input structure (Attributes), and the output structure (Varyings)
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
       
        float4 SourceSize;
        float4 GetSource(half2 uv, float2 pixelOffset = 0.0) {
        pixelOffset *= SourceSize.zw;
        return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + pixelOffset, 0);
        }
        float4 ColorPyramidGenerate (Varyings input) : SV_Target
        {
         
            float4 colors[4]={
                    GetSource(input.texcoord, float2(-1, -1)).rgba,
                    GetSource(input.texcoord, float2(-1, 1)).rgba,
                    GetSource(input.texcoord, float2(1, -1)).rgba,
                    GetSource(input.texcoord, float2(1, 1)).rgba
                };
                
              
         
          return (colors[0]+colors[1]+colors[2]+colors[3])/4.0;
       
            
        }
 
   
    ENDHLSL
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off
        Pass
        {
            Name "ColorPyramidBlit"

            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment ColorPyramidGenerate
            
            ENDHLSL
        }
       
        
    }
}