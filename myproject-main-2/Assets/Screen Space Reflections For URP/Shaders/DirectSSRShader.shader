Shader "Hidden/DirectSSRShader"
{

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
           #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"  
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"  
           #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"  
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"  

            uniform float4 ProjectionParams2;
            uniform float4 CameraViewTopLeftCorner;
            uniform float4 CameraViewXExtent;
            uniform float4 CameraViewYExtent;



            uniform Texture2D HiZBufferTexture;
          
            uniform int MaxHiZBufferTextureMipLevel;
            uniform float SSRBlendFactor;
            SamplerState sampler_point_clamp;
               SamplerState sampler_linear_clamp ;
            SamplerState sampler_linear_repeat ;
            uniform float4 SSRSourceSize;
            uniform int MaxIterations;
            uniform float SSRThickness;
            uniform float MaxTracingDistance;
               uniform float SSRMinSmoothness;
            uniform int UseColorPyramid;
            uniform int UseTemporalFilter;
            uniform int UseNormalImportanceSampling;
          
 

 
            float ProjectionDepthToLinearDepth(float depth,bool isTestDepth)
            {
                
                if(isTestDepth){
                      #if  UNITY_REVERSED_Z
                    return LinearEyeDepth(1-depth,_ZBufferParams);
                    #else
                     return LinearEyeDepth(depth,_ZBufferParams);
                    #endif
                    } else{
                         return LinearEyeDepth(depth,_ZBufferParams);
                        }
                
                 
              
                     
          
               
            }
           
            
                 uniform  Texture2D CameraLumTex;
                 float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness)
                    {
                        float a = roughness * roughness;
	
                        float phi = 2.0 * PI * Xi.x;
                        float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
                        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
	
	                    // from spherical coordinates to cartesian coordinates - halfway vector
                        float3 H;
                        H.x = cos(phi) * sinTheta;
                        H.y = sin(phi) * sinTheta;
                        H.z = cosTheta;
	
	                    // from tangent-space H vector to world-space sample vector
                        float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
                        float3 tangent = normalize(cross(up, N));
                        float3 bitangent = cross(N, tangent);
	
                        float3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
                        return normalize(sampleVec);
                    }


                    float Random2DTo1D(float2 value,float a ,float2 b)
                    {			
	                    //avaoid artifacts
	                    float2 smallValue = sin(value);
	                    //get scalar value from 2d vector	
	                    float  random = dot(smallValue,b);
	                    random = frac(sin(random) * a);
	                    return random;
                    }

                    float2 Random2DTo2D(float2 value){
	                    return float2(
		                    Random2DTo1D(value,14375.5964, float2(15.637, 76.243)),
		                    Random2DTo1D(value,14684.6034,float2(45.366, 23.168))
	                    );
                    }
                  
        
            
            float3 ReconstructViewPos(float2 uv, float linearEyeDepth) {  
             
                #if UNITY_UV_STARTS_AT_TOP
                uv.y = 1.0 - uv.y;  
                #endif
                float zScale = linearEyeDepth * ProjectionParams2.x; // divide by near plane  
                float3 viewPos = CameraViewTopLeftCorner.xyz + CameraViewXExtent.xyz * uv.x + CameraViewYExtent.xyz * uv.y;  
                viewPos *= zScale;  
                return viewPos;  
            }




            float4 DirectSSR(Varyings input):SV_TARGET{
              float rawDepth1=SampleSceneDepth(input.texcoord); 
              float linearDepth = LinearEyeDepth(rawDepth1, _ZBufferParams);
                
              float3 vnormal = (SampleSceneNormals(input.texcoord).xyz);

              float3 rayOriginWorld = ReconstructViewPos(input.texcoord,linearDepth)+ProjectionParams2.yzw; 

              float3 vDir=normalize(rayOriginWorld - ProjectionParams2.yzw);
              float3 rDir = reflect(vDir, normalize(vnormal));

              float3 marchPos=rayOriginWorld+vnormal*0.3*(linearDepth/100.0);//A small bias to prevent self-reflections
              float strideLen=0.25;//stride length
              UNITY_LOOP
              for(int i=0;i<MaxIterations;i++){
                marchPos+=strideLen*rDir;//Get a new march position
                float3 viewPos=mul(UNITY_MATRIX_V,float4(marchPos,1)).xyz;//In unity matrix mulplication, matrix should be on the left
              
                float4 projectionPos=mul(UNITY_MATRIX_P,float4(viewPos,1)).xyzw;//Transform the point to the texture space
                projectionPos.xyz/=projectionPos.w;
                projectionPos.xy=  projectionPos.xy*0.5+0.5;
                #if UNITY_UV_STARTS_AT_TOP
                float2 uv=float2(projectionPos.x,1-projectionPos.y);
                #else
                float2 uv=float2(projectionPos.x,projectionPos.y);
                #endif
                float testDepth=projectionPos.z;//Compare the result depth value by the testing-point texture space transformation
                float sampleDepth=SampleSceneDepth(uv);//With the depth sampled from the scene using UV by the testing-point texture space transformation

                float linearTestDepth=LinearEyeDepth(testDepth, _ZBufferParams);//Use linear eye depth for intersection testing
                float linearSampleDepth=LinearEyeDepth(sampleDepth, _ZBufferParams);

                if(uv.x<0||uv.x>1||uv.y<0||uv.y>1){
                break;//Terminate testing points that are out of the screen space
                }
                #define DEPTH_TESTING_THERESHOLD 0.2
                if(linearTestDepth>linearSampleDepth&&abs(linearSampleDepth-linearTestDepth)<DEPTH_TESTING_THERESHOLD){//If the testing point is below the surface and not too much below
                if(linearTestDepth<_ProjectionParams.y||linearTestDepth>_ProjectionParams.z*0.9){
                break;//Terminate intersections that are out of range
                }
                 return SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_point_clamp,uv);//Simply return scene color of the intersection point.
                }
           
              }
              return float4(0,0,0,0);//Not intersected 
            }
            
           
            float4 TextureSpaceSSR(Varyings input):SV_TARGET{
                float rawDepth1=SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,input.texcoord,0);//"HiZBufferTexture" is just used as regular depth buffers here 
                float linearDepth = LinearEyeDepth(rawDepth1, _ZBufferParams);
                if(linearDepth>_ProjectionParams.z*0.9){
                return float4(0,0,0,0);
                }
                float3 vnormal = (SampleSceneNormals(input.texcoord).xyz);

                float3 rayOriginWorld = ReconstructViewPos(input.texcoord,linearDepth)+ProjectionParams2.yzw;

                float3 vDir=normalize(rayOriginWorld - ProjectionParams2.yzw);
                float3 rDir = reflect(vDir, normalize(vnormal));//Get world space position and reflecting direction of current shading point first
                
                float maxDist=500.0; 

                float3 rayOriginInVS=mul(UNITY_MATRIX_V,float4(rayOriginWorld,1)).xyz;

                float4 rayOriginHS=mul(UNITY_MATRIX_P,float4(rayOriginInVS,1)).xyzw;//Homogeneous clip space ray origin
                float rayW=rayOriginHS.w;

                float3 rDirInVS=mul(UNITY_MATRIX_V,float4(rDir,0)).xyz;
               
                float end = rayOriginInVS.z + rDirInVS.z * maxDist;
                if (end > - _ProjectionParams.y)
                {
                   maxDist = (-_ProjectionParams.y - rayOriginInVS.z) / rDirInVS.z; //Prevent the endpoint from going to the back side of camera
                }
            
                float3 rayEndInVS=rayOriginInVS+rDirInVS*maxDist;//First transform the ray origin and direction into view space to get the endpoint of the ray in view space
               
              
                float4 rayEndHS=mul(UNITY_MATRIX_P,float4(rayEndInVS.xyz,1));
                rayEndHS.xyz/=rayEndHS.w;
                rayOriginHS.xyz/=rayOriginHS.w;//Perspective devide 
               
                float3 rayOriginTS=float3(rayOriginHS.x*0.5+0.5,(rayOriginHS.y*0.5+0.5),rayOriginHS.z);
                float3 rayEndTS=float3(rayEndHS.x*0.5+0.5,(rayEndHS.y*0.5+0.5),rayEndHS.z);

                #if UNITY_UV_STARTS_AT_TOP
                rayOriginTS.y=1-rayOriginTS.y;
                rayEndTS.y=1-rayEndTS.y;
                #endif
                
                #if UNITY_REVERSED_Z
                //Unity uses reversed Z method to store depth data of the scene for better precision in far distance so
                //the depth value is between 1 and 0. I tried to manually re-reverse it into [0,1] but ran into aliasing
                //probably due to precision lost, so I commented code below out.
                //
                //  rayOriginTS.z=1.0-rayOriginTS.z;
                //  rayEndTS.z=1.0-rayEndTS.z;
                #endif
               
                float3 rDirInTS=normalize(rayEndTS-rayOriginTS);//Reflection ray direction in Texture Space
                float outMaxDistance = rDirInTS.x >= 0 ? (1 - rayOriginTS.x) / rDirInTS.x : -rayOriginTS.x / rDirInTS.x;
                outMaxDistance = min(outMaxDistance, rDirInTS.y < 0 ? (-rayOriginTS.y / rDirInTS.y) : ((1 - rayOriginTS.y) / rDirInTS.y));
                outMaxDistance = min(outMaxDistance, rDirInTS.z < 0 ? (-rayOriginTS.z / rDirInTS.z) : ((1 - rayOriginTS.z) / rDirInTS.z));//Use a "max distance" to clamp the textue space reflection endpoint


               
               float3 reflectionEndTS=rayOriginTS + rDirInTS * outMaxDistance;//to make sure it won't go out the "Texture Space" box
               float3 dp = reflectionEndTS.xyz - rayOriginTS.xyz;//Texture Space delta between the ray origin and endpoint
               float2 originScreenPos = float2(rayOriginTS.xy *SSRSourceSize.xy);//The pixel position of the ray origin and endpoint. SSRSourceSize.xy stands for the width and height of screen.
               float2 endPosScreenPos = float2(reflectionEndTS.xy *SSRSourceSize.xy);
               float2 pixelDelta=endPosScreenPos - originScreenPos;//Pixel delta between the ray origin and endpoint
               float max_dist = max(abs(pixelDelta.y), abs(pixelDelta.x));//Get max value between two components of pixelDelta
               dp /= max_dist;//Divide dp by max_dist to get raymarching stride length so we can make sure every pixel along the ray route will be covered.
             
                float4 marchPosInTS = float4(rayOriginTS.xyz+dp, 0);
                float4 rayDirInTS = float4(dp.xyz, 0);
	            float4 rayStartPos = marchPosInTS;
                bool isIntersected=false;
                UNITY_LOOP
                    for(int i = 0; i<MaxIterations;i ++)
                    {
	                float rawDepth = SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,marchPosInTS.xy,0);
                    float testRawDepth=marchPosInTS.z;
                    #if UNITY_REVERSED_Z
              //      testRawDepth=1.0-testRawDepth;
                    #endif
                    float sampleLinearDepth=LinearEyeDepth(rawDepth,_ZBufferParams);//Use linear depth to check intersection
                    float testLinearDepth=LinearEyeDepth(testRawDepth,_ZBufferParams);

	                float thickness = abs(testLinearDepth - sampleLinearDepth);


                    if(marchPosInTS.x<0||marchPosInTS.y<0||marchPosInTS.x>1||marchPosInTS.y>1 )
	                {
	                     isIntersected=false;
		                break;
	                }
                    #define MAX_THICKNESS_DIFFERENCE_TO_HIT 0.01*rayW
	                if(testLinearDepth>=sampleLinearDepth&&thickness<MAX_THICKNESS_DIFFERENCE_TO_HIT)//We use a constant thickness to decide has the test point intersected a surface or it just go below the surface,
                    //but this will cause intersection miss on some shading points and produce strip aliasing. Maybe a magic number can help.
	                {
                    if(testLinearDepth>_ProjectionParams.z*0.9||sampleLinearDepth>_ProjectionParams.z*0.9){
                    isIntersected=false;
		                break;
                    }
	                     isIntersected=true;
		                break;
	                }
		
                        marchPosInTS += rayDirInTS;
                    }
                    if(isIntersected==true){
                    float2 uv=marchPosInTS.xy;
                    return SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_point_clamp,uv);
                    
                    }else{
                    return float4(0,0,0,0);
                    }
            }

            #define PI 3.1415926
        
                float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
                {
                    return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
                }

                float fresnelSchlickRoughness(float cosTheta, float F0, float roughness)
                {
                    return F0 + (max(1.0 - roughness, F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
                }
 
                  uniform sampler2D _GBuffer1;  
                   uniform sampler2D _GBuffer0;  
                   SamplerState sampler_Trilinear_Clamp;
         
                 uniform Texture2D SSRResultTex;
                 uniform Texture2D BRDFLutTex;


                   uniform Texture2D ColorPyramidTexture;
                   uniform float MaxColorPyramidMipLevel;

                   uniform Texture2D PrevSSRBlendResult;

                   uniform float4 AmbientSH[7];



                    TEXTURE2D_X(_MotionVectorTexture);
                    SAMPLER(sampler_MotionVectorTexture);
                    
                   

                    void AdjustColorBox(float2 uv, inout float3 boxMin, inout float3 boxMax,Texture2D tex) {
                         const float2 kOffssets3x3[9]={
                        float2(0,0),
                        float2(1,1),
                        float2(-1,-1),
                        float2(-1,1),
                        float2(1,-1),
                        float2(0,1),
                        float2(1,0),
                        float2(0,-1),
                        float2(-1,0)
                        };
                        boxMin = 1.0;
                        boxMax = 0.0;

                        UNITY_UNROLL
                        for (int k = 0; k < 9; k++) {
                            float3 C = RGBToYCoCg(SAMPLE_TEXTURE2D_X(tex,sampler_point_clamp,uv + kOffssets3x3[k] * SSRSourceSize.zw*2));
                            boxMin = min(boxMin, C);
                            boxMax = max(boxMax, C);
                        }
                    }
                           #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"  
                               #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"  





                               half3 GlobalIlluminationCustom(BRDFData brdfData,
                                    half3 bakedGI, float3 positionWS,
                                    half3 normalWS, half3 viewDirectionWS, float3 indirectSpecular1)
                                {
                                    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
                                    half NoV = saturate(dot(normalWS, viewDirectionWS));
                                    half fresnelTerm = Pow4(1.0 - NoV);

                                    half3 indirectDiffuse = bakedGI;
                                    half3 indirectSpecular = indirectSpecular1;

                                    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

                                    if (IsOnlyAOLightingFeatureEnabled())
                                    {
                                        color = half3(1,1,1); // "Base white" for AO debug lighting mode
                                    }

                           
                                    return color;
                               
                                }
            float4 SSRComposite(Varyings input):SV_Target{
                float4 reflResult=SAMPLE_TEXTURE2D_X(SSRResultTex,sampler_point_clamp,input.texcoord);
               return reflResult;
                
            }
            float4 SSRFinalBlend(Varyings input):SV_TARGET{
               return SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_point_clamp,input.texcoord);
            }
     ENDHLSL
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
       
        Pass
        {
            Name "SSRTracing"

            HLSLPROGRAM
            #pragma multi_compile _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile _ SSR_USE_FORWARD_RENDERING
            #pragma vertex Vert
            #pragma fragment TextureSpaceSSR
            
            ENDHLSL
        }
          Blend Off
        Pass
        {
         
            Name "SSRComposite"

            HLSLPROGRAM
            #pragma multi_compile _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile _ SSR_USE_FORWARD_RENDERING
            #pragma vertex Vert
            #pragma fragment SSRComposite
            
            ENDHLSL
        }
          Blend SrcAlpha OneMinusSrcAlpha
         Pass
        {
         
            Name "SSRFinalBlend"

            HLSLPROGRAM
            #pragma multi_compile _ _GBUFFER_NORMALS_OCT
               #pragma multi_compile _ SSR_USE_FORWARD_RENDERING
            #pragma vertex Vert
            #pragma fragment SSRFinalBlend
            
            ENDHLSL
        }
    }
}