Shader "Hidden/SSRShader"
{
    HLSLINCLUDE
    
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        // The Blit.hlsl file provides the vertex shader (Vert),
        // the input structure (Attributes), and the output structure (Varyings)
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
            float3 ReconstructViewPos(float2 uv, float linearEyeDepth) {  
             
                #if UNITY_UV_STARTS_AT_TOP
                uv.y = 1.0 - uv.y;  
                #endif
                float zScale = linearEyeDepth * ProjectionParams2.x; // divide by near plane  
                float3 viewPos = CameraViewTopLeftCorner.xyz + CameraViewXExtent.xyz * uv.x + CameraViewYExtent.xyz * uv.y;  
                viewPos *= zScale;  
                return viewPos;  
            }

            float4 TransformViewToHScreen(float3 vpos,float2 screenSize) {  
                float4 cpos = mul(UNITY_MATRIX_P, float4(vpos,1));  
                cpos.xy = float2(cpos.x, cpos.y * _ProjectionParams.x) * 0.5 + 0.5 * cpos.w;  
                cpos.xy *= screenSize;  
                return cpos;  
            }  





            float linearDepthToProjectionDepth(float linearDepth, float near, float far)
            {
                return (1.0 / linearDepth - 1.0 / near) / (1.0 / far - 1.0 / near);
            }
            float ProjectionDepthToLinearDepth(float depth,bool isTestDepth)
            {
                
                if(isTestDepth){
                      #if  UNITY_REVERSED_Z
                    return LinearEyeDepth(depth,_ZBufferParams);
                    #else
                     return LinearEyeDepth(depth,_ZBufferParams);
                    #endif
                    } else{
                         return LinearEyeDepth(depth,_ZBufferParams);
                        }
                
                 
              
                     
          
               
            }
            float3 IntersectDepthPlane(float3 RayOrigin, float3 RayDir, float t)
            {
                return RayOrigin + RayDir * t;
            }

            float2 GetCellCount(float2 Size, float Level)
            {
                return floor(Size / (Level > 0.0 ? exp2(Level) : 1.0));
            }

            float2 GetCell(float2 pos, float2 CellCount)
            {
                return floor(pos * CellCount);
            }
            float GetMinimumDepthPlane(float2 p, int mipLevel)
            {
         //       int mipLevel1=clamp(mipLevel,0,MaxHiZBufferTextureMipLevel);
                #if UNITY_REVERSED_Z
                return SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,p,mipLevel).x;
                #else
                  return SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,p,mipLevel).x;
                #endif
            }
              float GetMaximumDepthPlane(float2 p, int mipLevel)
            {
         //       int mipLevel1=clamp(mipLevel,0,MaxHiZBufferTextureMipLevel);
                #if UNITY_REVERSED_Z
                return SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,p,mipLevel).y;
                #else
                  return SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,p,mipLevel).y;
                #endif
            }
            float3 IntersectCellBoundary(float3 o, float3 d, float2 cell, float2 cell_count, float2 crossStep, float2 crossOffset)
            {
                float3 intersection = 0;
	
                float2 index = cell + crossStep;
                float2 boundary = index / cell_count;
            //    boundary += crossOffset;
	
                float2 delta = boundary - o.xy;
                delta /= d.xy;
                float t = min(delta.x, delta.y);
   
                intersection = IntersectDepthPlane(o, d, t);
               intersection.xy += (delta.x < delta.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);
                return intersection;
            }
            inline bool FloatEqApprox(float a, float b) {
                const float eps = 0.00001f;
                return abs(a - b) < eps;
            }
            bool CrossedCellBoundary(float2 CellIdxA, float2 CellIdxB)
            {
              //  return CellIdxA.x!=CellIdxB.x || CellIdxA.y!=CellIdxB.y;
                return !FloatEqApprox( CellIdxA.x,CellIdxB.x) || !FloatEqApprox( CellIdxA.y,CellIdxB.y);
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

            float4 SSRTracing(Varyings input):SV_Target{
                  float rawDepth1=SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,input.texcoord,0);
                  float linearDepth = LinearEyeDepth(rawDepth1, _ZBufferParams);
                
                   float3 vnormal = (SampleSceneNormals(input.texcoord).xyz);
                
                 
             


                  float3 rayOriginWorld = ReconstructViewPos(input.texcoord,linearDepth)+ProjectionParams2.yzw; 
                  #if SSR_USE_FORWARD_RENDERING
                        float roughness=0.04;
                  #else 
                        float roughness=1-SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_point_clamp,input.texcoord).a;
                  #endif
             
                   UNITY_BRANCH
                   if(1.0f-roughness<SSRMinSmoothness){
                       return float4(0,0,0,0);
                       }

                  float3 vDir=normalize(rayOriginWorld - ProjectionParams2.yzw);
                  float3 rDir = reflect(vDir, normalize(vnormal));
                  float3 finalRDir=rDir;

                      
                      
                  UNITY_BRANCH
                   if(UseNormalImportanceSampling){
                     
                
                    float2 randomVal=Random2DTo2D(input.texcoord+float2(_Time.y,-_Time.y));
                    float3 importanceSampleRDir=normalize(ImportanceSampleGGX(randomVal,vnormal,roughness));

                        rDir = reflect(vDir, normalize(importanceSampleRDir));
                    finalRDir=rDir;
                    int k=0;
                         while(dot(vnormal,rDir)<0&&k<8){
                             randomVal=Random2DTo2D(input.texcoord+float2(_Time.y+((float)k)/100.0,-_Time.y-((float)k)/130.0));
                        importanceSampleRDir=normalize(ImportanceSampleGGX(randomVal,vnormal,roughness));

                        rDir = reflect(vDir, normalize(importanceSampleRDir));
                         k++;
                         }
                       }
                        finalRDir=rDir;
                  
                     

                         
                  rayOriginWorld=rayOriginWorld+ vnormal * 0.7*(linearDepth / 100.0) ;
                //  return float4(linearDepth.xxx/100,1);
                  float3 viewPosOrigin=mul(UNITY_MATRIX_V,float4(rayOriginWorld.xyz,1)).xyz;
                 float3 viewRDir = normalize(mul(UNITY_MATRIX_V,float4(finalRDir, 0)).xyz);
                 float maxDist =1000;


                   float end = viewPosOrigin.z + viewRDir.z * maxDist;
                    if (end > - _ProjectionParams.y)
                    {
                        maxDist = (-_ProjectionParams.y - viewPosOrigin.z) / viewRDir.z;
                    }
                        float3 viewPosEnd = viewPosOrigin + viewRDir * maxDist;
                        float4 startHScreen = TransformViewToHScreen(viewPosOrigin, SSRSourceSize.xy);
                        float4 endHScreen = TransformViewToHScreen(viewPosEnd,  SSRSourceSize.xy);
                            float startK = 1.0 / startHScreen.w;
                            float endK = 1.0 / endHScreen.w;
                            float3 startScreen = startHScreen.xyz * startK;
                             float3 endScreen = endHScreen.xyz * endK;
                 #if  UNITY_REVERSED_Z
             //     startScreen.z=1-startScreen.z;
              //    endScreen.z=1-endScreen.z;


              //  return float4(startScreen.zzz,1);
                

                #endif
                    float3 startScreenTextureSpace = float3(startScreen.xy * SSRSourceSize.zw, startScreen.z);
                    float3 endScreenTextureSpace = float3(endScreen.xy *  SSRSourceSize.zw, endScreen.z);

                     float3 reflectDirTextureSpace = normalize(endScreenTextureSpace - startScreenTextureSpace);
    
    
    
                    float outMaxDistance = reflectDirTextureSpace.x >= 0 ? (1 - startScreenTextureSpace.x) / reflectDirTextureSpace.x : -startScreenTextureSpace.x / reflectDirTextureSpace.x;
                    outMaxDistance = min(outMaxDistance, reflectDirTextureSpace.y < 0 ? (-startScreenTextureSpace.y / reflectDirTextureSpace.y) : ((1 - startScreenTextureSpace.y) / reflectDirTextureSpace.y));
                    outMaxDistance = min(outMaxDistance, reflectDirTextureSpace.z < 0 ? (-startScreenTextureSpace.z / reflectDirTextureSpace.z) : ((1 - startScreenTextureSpace.z) / reflectDirTextureSpace.z));

                  //  outMaxDistance=1;


                    
                       bool isIntersecting = false;

                        int maxLevel = MaxHiZBufferTextureMipLevel;
                        float2 crossStep = float2(reflectDirTextureSpace.x >= 0 ? 1 : -1, reflectDirTextureSpace.y >= 0 ? 1 : -1);
                        float2 crossOffset = crossStep.xy / ( SSRSourceSize.xy) / 32.0;
                       
                        crossStep = saturate(crossStep);
        
                        float3 ray = startScreenTextureSpace.xyz;
                        float minZ = ray.z;
                        float maxZ = ray.z + reflectDirTextureSpace.z * outMaxDistance;
    
                        float deltaZ = (maxZ - minZ);

                        float3 o = ray;
                        float3 d = reflectDirTextureSpace * outMaxDistance;
    
    
                        int startLevel =0;
                        int stopLevel = 0;
    
    
                        float2 startCellCount = GetCellCount( SSRSourceSize.xy, startLevel);
	
                        float2 rayCell = GetCell(ray.xy, startCellCount);
                        ray = IntersectCellBoundary(o, d, rayCell, startCellCount, crossStep, crossOffset);
    
                        int level = startLevel;
                        uint iter = 0;
                     #if UNITY_REVERSED_Z
                        bool isBackwardRay = reflectDirTextureSpace.z> 0;
                        float rayDir = isBackwardRay ? 1 : -1;
                     #else
                      bool isBackwardRay = reflectDirTextureSpace.z< 0;
                        float rayDir = isBackwardRay ? -1 : 1;

                     #endif
                       
                        UNITY_LOOP
                        while (level >= stopLevel &&  ray.z*rayDir <= maxZ*rayDir &&iter <MaxIterations)
                        {
        
                            float2 cellCount = GetCellCount( SSRSourceSize.xy, level);
                             float2 oldCellIdx = GetCell(ray.xy, cellCount);
                             
                                     float cell_minZ =GetMinimumDepthPlane((oldCellIdx+0.5f) / cellCount, level);
                                float cell_maxZ=GetMaximumDepthPlane((oldCellIdx+0.5f) / cellCount, level);
                       
                #if UNITY_REVERSED_Z
                            float3 tmpRay = (((cell_minZ)< ray.z) && !isBackwardRay) ? IntersectDepthPlane(o, d, ((cell_minZ) - minZ) / deltaZ) : ray;

                         /*   if(isBackwardRay==true){
                            tmpRay = (((1-cell_maxZ)< ray.z)) ? IntersectDepthPlane(o, d,((1-cell_maxZ) - minZ) / deltaZ) : ray;
                            }*/
                #else
                            float3 tmpRay = (((cell_minZ)> ray.z) && !isBackwardRay) ? IntersectDepthPlane(o, d,((cell_minZ) - minZ) / deltaZ) : ray;

                            
                             /*  if(isBackwardRay==true){
                            tmpRay = (((cell_maxZ)< ray.z)) ? IntersectDepthPlane(o, d,((cell_maxZ) - minZ) / deltaZ) : ray;
                            }*/
                #endif
                             float2 newCellIdx = GetCell(tmpRay.xy, cellCount);
        
                            float thickness = 0;
                            float thicknessMaxZ=0;
                            float rayZLinear = ProjectionDepthToLinearDepth(ray.z, true);
                            float cellMinZLinear = ProjectionDepthToLinearDepth(cell_minZ,false);
                             float cellMaxZLinear = ProjectionDepthToLinearDepth(cell_maxZ,false);
                            if (level == stopLevel)
                            {
                                thickness = abs(rayZLinear
                                 - cellMinZLinear);
                                 thicknessMaxZ= abs(rayZLinear
                                 - cellMaxZLinear);
                            }
                            else
                            {
                            thicknessMaxZ=0;
                                thickness = 0;
          
                            }
                            bool crossed = false;
                            bool crossedBehind = false;
                           // (isBackwardRay && ) ||
                            if (isBackwardRay)
                            {
                                if ((cellMinZLinear > rayZLinear ))
                                {
                                    crossed = true;
                                
                                }else if((cellMinZLinear+0.02  <rayZLinear && thickness >= SSRThickness*1.1)){
                                crossedBehind = true;
                               
          
                                    }
                                }
                           else if ((cellMinZLinear+0.02< rayZLinear && thickness >= SSRThickness*1.1))
                            {
                                crossedBehind = true;//tracing ray behind downgrades into linear search
      //
                            }

                            else if (CrossedCellBoundary(oldCellIdx, newCellIdx))
                            {
                                crossed = true;
                            }
                            else
                            {
                                crossed = false;
                            }
        
       
      
                            if (crossed == true||crossedBehind == true)
                            {
                               if( rayZLinear >  _ProjectionParams.z*0.9 || cellMinZLinear > _ProjectionParams.z*0.9){
                                        isIntersecting = false;
                                        break;
                                     }else{
                                       ray = IntersectCellBoundary(o, d, oldCellIdx, cellCount, crossStep, crossOffset);
                                    level = min(level + 1.0f,maxLevel);
                                     }
                              
         

                            }
                           
                            else
                            {
                                ray = tmpRay;
                                level = max(level - 1, 0);
          

                            }
                            [branch]
                            if (ray.x < 0 || ray.y < 0 || ray.x > 1 || ray.y > 1)
                            {
                                isIntersecting = false;
                                break;
                            }
         
                            
                            if (level <= stopLevel&&crossed==false&&crossedBehind==false )
                            {
                                float2 cellCount1 = GetCellCount( SSRSourceSize.xy, level);
                                 float2 oldCellIdx1 = GetCell(ray.xy, cellCount1);
                                     float cell_minZ1 =GetMinimumDepthPlane((oldCellIdx1+0.5f) / cellCount1, level);
                                float cell_maxZ1 =GetMaximumDepthPlane((oldCellIdx1+0.5f) / cellCount1, level);
                              float   rayZLinear1 = ProjectionDepthToLinearDepth(ray.z,true);
                                float cellMinZLinear1 = ProjectionDepthToLinearDepth(cell_minZ1,false);
                               float thickness1 = (rayZLinear1
                                 - cellMinZLinear1);
         /*   if(isBackwardRay==true){
             cellMinZLinear1 = ProjectionDepthToLinearDepth(cell_maxZ1,false);
               thickness1 = (rayZLinear1
                                 - cellMinZLinear1);
            }*/

                           
                                if (thickness1 < SSRThickness && rayZLinear1 > cellMinZLinear1 -0.06 && rayZLinear1 <  _ProjectionParams.z*0.9 && cellMinZLinear1 < _ProjectionParams.z*0.9)
                                {
                                    if( rayZLinear1 >  _ProjectionParams.z*0.9 || cellMinZLinear1 > _ProjectionParams.z*0.9){
                                        isIntersecting = false;
                                        break;
                                     }
                                    
                                    isIntersecting = true;
                                    break;
                                } 
                                else{

                                    isIntersecting=false;
                                 }
          
            
          
                            }
      
                            ++iter;
                            
                        }

                       
                       /*   float3 dp = endScreenTextureSpace.xyz - startScreenTextureSpace.xyz;
                            int2 sampleScreenPos = int2(startScreenTextureSpace.xy *SSRSourceSize.xy);
                            int2 endPosScreenPos = int2(endScreenTextureSpace.xy * SSRSourceSize.xy);
                            int2 dp2 = endPosScreenPos - sampleScreenPos;
                            const int max_dist = max(abs(dp2.x), abs(dp2.y));
                            dp /= max_dist;
                               float4 rayPosInTS = float4(startScreenTextureSpace.xyz + dp, 0);
                                float4 vRayDirInTS = float4(dp.xyz, 0);
	                            float4 rayStartPos = rayPosInTS;
                              
                                UNITY_LOOP
                                  for(int i = 0;i<max_dist && i<500;i ++)
                                    {
	                                float depth=GetMinimumDepthPlane(rayPosInTS.xy,0);
                                      float depthLinear = ProjectionDepthToLinearDepth(depth,false);
                                     float rayDepthLinear = ProjectionDepthToLinearDepth(rayPosInTS.z,true);
	                                float thickness = rayDepthLinear - depthLinear;

                                        if (rayPosInTS.x < 0 || rayPosInTS.y < 0 || rayPosInTS.x > 1 || rayPosInTS.y > 1)
                                        {
                                            isIntersecting = false;
                                            break;
                                        }
	                                if( abs(thickness)<0.4&&rayDepthLinear>depthLinear )
	                                {
	                                     isIntersecting=true;
		                                break;
	                                } 
		
                                        rayPosInTS += vRayDirInTS;
                                    }
                                
                                    */
                    float2 uv =ray.xy;
                
                        if(isIntersecting==true){
               //               return SAMPLE_TEXTURE2D_X(CameraLumTex,sampler_point_clamp,uv);
                            
                  float rawDepth2=SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,uv,0);
                  float linearDepth2 = LinearEyeDepth(rawDepth2, _ZBufferParams);
                  float3 hitPosWorld = ReconstructViewPos(uv,linearDepth2)+ProjectionParams2.yzw; 
                    float rayLength=length(hitPosWorld-rayOriginWorld);
                            if(isBackwardRay==true){
                          //      return float4(1,1,1,1);
                            }
                             return float4(uv.xy,rayLength/100.0f,1);//SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_point_clamp,uv);
                            }else{
                          //    return float4(uv.xy,rayLength/100.0f,1);
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
                                    half fresnelTerm = pow(1.0 - NoV,2);

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
         //     return reflResult;
               
               
                float rawDepth1=SAMPLE_TEXTURE2D_X_LOD(HiZBufferTexture,sampler_point_clamp,input.texcoord,0);
                float linearDepth = LinearEyeDepth(rawDepth1, _ZBufferParams);
                float3 worldPos= ReconstructViewPos(input.texcoord,linearDepth)+ProjectionParams2.yzw; 
                float3 normal=(SampleSceneNormals(input.texcoord).xyz);
                     #if SSR_USE_FORWARD_RENDERING
                float roughness=0.04;
                float metalness=0.8;
               #else
                    float roughness=1-SAMPLE_TEXTURE2D_X(_CameraNormalsTexture,sampler_point_clamp,input.texcoord).a;
                float metalness=tex2D(_GBuffer1,input.texcoord).x;
               #endif
              
                 float rayLengthGlossyAmp=reflResult.z*roughness*MaxColorPyramidMipLevel;
              

                float3 reflLum;
                if(UseColorPyramid){
                    reflLum=SAMPLE_TEXTURE2D_X_LOD(ColorPyramidTexture,sampler_Trilinear_Clamp,reflResult.xy,clamp(roughness*MaxColorPyramidMipLevel,0,MaxColorPyramidMipLevel)).xyz;
                    }
                    else{
                            reflLum=SAMPLE_TEXTURE2D_X(CameraLumTex,sampler_linear_clamp,reflResult.xy).xyz;
                        } 

                float3 viewDir=normalize(worldPos-ProjectionParams2.yzw);

                float3 lightPos= ReconstructViewPos(reflResult.xy,LinearEyeDepth(SampleSceneDepth(reflResult.xy), _ZBufferParams))+ProjectionParams2.yzw;
              
                #if SSR_USE_FORWARD_RENDERING
                  float3 albedo=reflLum;
                #else
              float3 albedo=(tex2D(_GBuffer0,input.texcoord).xyz);
              #endif
                 float3 reflDir= reflect(viewDir, normal);
               
                 BRDFData brdfData;
                 float alpha=1;
                 InitializeBRDFData(albedo,metalness,metalness,1-roughness,alpha,brdfData);
              
                float3 diffuse=SampleSH9(AmbientSH,normal);
            //   return float4(diffuse.xyz,1);
                   float3 resultCol=GlobalIlluminationCustom(brdfData,diffuse,worldPos,normal,-viewDir,reflLum);
          
                float resultLum=dot(resultCol,float3(0.2126,0.7152,0.0722));
                 
                    half NoV = saturate(dot(normal, -viewDir));
                                    half fresnelTerm = pow(1.0 - NoV,2);
            
                if(UseTemporalFilter!=0){
                        float2 motionVec=  SAMPLE_TEXTURE2D_X(_MotionVectorTexture, sampler_MotionVectorTexture, input.texcoord).xy;
                float frameInfl=saturate( length(motionVec)*100);
                float4 prevColor=SAMPLE_TEXTURE2D_X(PrevSSRBlendResult,sampler_point_clamp,input.texcoord-motionVec);
              

              
             
                    if(reflResult.a<0.1){
                    return lerp(float4(0,0,0,0),prevColor,0.97*(1.0-frameInfl));
                    } 
  
                    return lerp(float4(resultCol.xyz,SSRBlendFactor*fresnelTerm),prevColor,0.97*(1.0-frameInfl));
                    }else{
                        if(reflResult.a<0.1){
                        return float4(0,0,0,0);
                         }
                             return float4(resultCol.xyz,SSRBlendFactor*fresnelTerm);
                        }
            
                
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
            #pragma fragment SSRTracing
            
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