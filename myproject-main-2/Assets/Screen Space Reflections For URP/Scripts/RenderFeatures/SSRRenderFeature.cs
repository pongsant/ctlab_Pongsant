using System;
using System.Collections;
using System.Collections.Generic;
 
using Unity.Mathematics;
using Unity.VisualScripting;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;
using static UnityScreenSpaceReflections.HiZBufferRenderPass;
using Object = UnityEngine.Object;

namespace UnityScreenSpaceReflections
{
[RequireComponent(typeof(HiZBufferRenderFeature))]

public class SSRRenderFeature : ScriptableRendererFeature
{
    
   
    [SerializeField]private SSRRenderFeatureSettings settings;
    private Shader shader;
    private Material material;
    private SSRRenderPass ssrRenderPass;
   
     
    public override void Create()
    {
       

        
       
        shader = Shader.Find("Hidden/SSRShader");
        if (shader == null)
        {
            return;
        }
        if (settings == null)
        {
            settings = new SSRRenderFeatureSettings();
        }
        material = CoreUtils.CreateEngineMaterial(shader);

        //   material = new Material(shader);

        if (settings.isUsingForwardRendering == true)
        {
            material.EnableKeyword("SSR_USE_FORWARD_RENDERING");
        }
        else
        {
            material.DisableKeyword("SSR_USE_FORWARD_RENDERING");
        }

        if (ssrRenderPass != null)
        {
            Debug.Log("dispose ssr");
            ssrRenderPass.Dispose();
        }
            ssrRenderPass = new SSRRenderPass(material, settings,this);
        ssrRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;

    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game|| renderingData.cameraData.cameraType == CameraType.SceneView)
        {
            renderer.EnqueuePass(ssrRenderPass);
        }

        
       
    }
    protected override void Dispose(bool disposing)
    { ssrRenderPass.Dispose();
 /*   
#if UNITY_EDITOR
        if (EditorApplication.isPlaying)
        {
            Destroy(material);
        }
        else
        {
            DestroyImmediate(material);
        }
#else
                        Destroy(material);
#endif*/
    CoreUtils.Destroy(material);
    }
}

public class SSRRenderPass: ScriptableRenderPass
{
    private Material material;
    private SSRRenderFeatureSettings settings;
    private int sourceSizeUniformID;
    private int cameraViewTopLeftCornerUniformID;
    private int cameraViewXExtentUniformID;
    private int cameraViewYExtentUniformID;
    private int projectionParams2UniformID;
    private int maxIterationsUniformID;
    private int maxHiZMipLevelUniformID;
    private int cameraColorTexUniformID;
    private int ssrResultTexUniformID;
    
    private int ssrThicknessUniformID;
    private int maxTracingDistanceUniformID;
    private int useColorPyramidUniformID;
    private int useTemporalFilterUniformID;
    private int prevSSRBlendResultUniformID;
    private int useNormalImportanceSamplingUniformID;
    private int ssrBlendFactorUniformID;
    private int ssrMinSmoothnessUniformID;
    private int ssrAmbientSHUniformID;
    private RTHandle ssrRenderTarget;
    private RTHandle prevSSRBlendTarget;
    private RTHandle ssrBlendTarget;
    private RTHandle tmpCameraColorTarget;
    private RenderTextureDescriptor tmpCameraColorTextureDescriptor;
    private RenderTextureDescriptor ssrBlendTextureDescriptor;
    private RenderTextureDescriptor ssrRenderTextureDescriptor;
    private SSRRenderFeature ssrRenderFeature;
    public SSRRenderPass(Material material, SSRRenderFeatureSettings settings,SSRRenderFeature feature)
    {
        
        this.material = material;
        this.settings = settings;
        this.ssrRenderFeature= feature;
        sourceSizeUniformID = Shader.PropertyToID("SSRSourceSize");
        cameraViewTopLeftCornerUniformID= Shader.PropertyToID("CameraViewTopLeftCorner");
        cameraViewXExtentUniformID = Shader.PropertyToID("CameraViewXExtent");
        cameraViewYExtentUniformID = Shader.PropertyToID("CameraViewYExtent");
        projectionParams2UniformID = Shader.PropertyToID("ProjectionParams2");
        maxIterationsUniformID = Shader.PropertyToID("MaxIterations");
        maxHiZMipLevelUniformID= Shader.PropertyToID("MaxHiZBufferTextureMipLevel"); 
        cameraColorTexUniformID = Shader.PropertyToID("CameraLumTex");
        ssrResultTexUniformID = Shader.PropertyToID("SSRResultTex");
        useColorPyramidUniformID = Shader.PropertyToID("UseColorPyramid");
        ssrThicknessUniformID = Shader.PropertyToID("SSRThickness");
        maxTracingDistanceUniformID = Shader.PropertyToID("MaxTracingDistance");
        useTemporalFilterUniformID = Shader.PropertyToID("UseTemporalFilter");
        prevSSRBlendResultUniformID = Shader.PropertyToID("PrevSSRBlendResult");
        useNormalImportanceSamplingUniformID = Shader.PropertyToID("UseNormalImportanceSampling");
        ssrBlendFactorUniformID = Shader.PropertyToID("SSRBlendFactor");
        ssrAmbientSHUniformID = Shader.PropertyToID("AmbientSH");
        ssrMinSmoothnessUniformID = Shader.PropertyToID("SSRMinSmoothness");
        ssrRenderTextureDescriptor = new RenderTextureDescriptor(0,0,RenderTextureFormat.ARGBFloat,0,1);
        ssrRenderTextureDescriptor.sRGB = false;
        tmpCameraColorTextureDescriptor = new RenderTextureDescriptor(0, 0, RenderTextureFormat.ARGBFloat, 0, 1);
        tmpCameraColorTextureDescriptor.sRGB = true;
        ssrBlendTextureDescriptor = new RenderTextureDescriptor(0, 0, RenderTextureFormat.ARGBFloat, 0, 1);
        ssrBlendTextureDescriptor.sRGB= true;
     
        ConfigureInput(ScriptableRenderPassInput.Motion);
        ConfigureInput(ScriptableRenderPassInput.Normal);
        }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        if (material == null)
        {
            Debug.LogErrorFormat("{0}.Execute(): Missing material.", GetType().Name);
            return;
        }
        ConfigureInput(ScriptableRenderPassInput.Normal);
        ConfigureInput(ScriptableRenderPassInput.Motion);
        Matrix4x4 view = renderingData.cameraData.GetViewMatrix();
        Matrix4x4 proj = renderingData.cameraData.GetProjectionMatrix();
        Matrix4x4 vp = proj * view;

        
        Matrix4x4 cview = view;
        
        cview.SetColumn(3, new Vector4(0.0f, 0.0f, 0.0f, 1.0f));
        Matrix4x4 cviewProj = proj * cview;
 
        Matrix4x4 cviewProjInv = cviewProj.inverse;

     
        var near = renderingData.cameraData.camera.nearClipPlane;
   
        Vector4 topLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, 1.0f, -1.0f, 1.0f));
        Vector4 topRightCorner = cviewProjInv.MultiplyPoint(new Vector4(1.0f, 1.0f, -1.0f, 1.0f));
        Vector4 bottomLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, -1.0f, -1.0f, 1.0f));

      
        Vector4 cameraXExtent = topRightCorner - topLeftCorner;
        Vector4 cameraYExtent = bottomLeftCorner - topLeftCorner;

        near = renderingData.cameraData.camera.nearClipPlane;



        material.SetVector(cameraViewTopLeftCornerUniformID, topLeftCorner);
        material.SetVector(cameraViewXExtentUniformID, cameraXExtent);
        material.SetVector(cameraViewYExtentUniformID, cameraYExtent);
        material.SetVector(projectionParams2UniformID, new Vector4(1.0f / near, renderingData.cameraData.worldSpaceCameraPos.x, renderingData.cameraData.worldSpaceCameraPos.y, renderingData.cameraData.worldSpaceCameraPos.z));

    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
    
        var width = Math.Max((int)Math.Ceiling(Mathf.Log(cameraTextureDescriptor.width, 2) - 1.0f), 1);
        var height = Math.Max((int)Math.Ceiling(Mathf.Log(cameraTextureDescriptor.height, 2) - 1.0f), 1);
        if (HiZBufferRenderPass.downSample == false)
        {
            width = 2 << width;
            height = 2 << height;
        }
        else
        {
            width = 1 << width;
            height = 1 << height;
        }
       
        ssrRenderTextureDescriptor.width = width;
        ssrRenderTextureDescriptor.height = height;
         
        tmpCameraColorTextureDescriptor.width = width ;
        tmpCameraColorTextureDescriptor.height = height ;
        ssrBlendTextureDescriptor.width = width;
        ssrBlendTextureDescriptor.height = height;
        //Check if the descriptor has changed, and reallocate the RTHandle if necessary.
        RenderingUtils.ReAllocateIfNeeded(ref ssrRenderTarget, ssrRenderTextureDescriptor);
        RenderingUtils.ReAllocateIfNeeded(ref prevSSRBlendTarget, ssrBlendTextureDescriptor);
        RenderingUtils.ReAllocateIfNeeded(ref tmpCameraColorTarget, tmpCameraColorTextureDescriptor);
        RenderingUtils.ReAllocateIfNeeded(ref ssrBlendTarget, ssrBlendTextureDescriptor);
    }

    public void GetSHVectorArrays(Vector4[] result, ref SphericalHarmonicsL2 sh)
    {
        for (int i = 0; i < 3; i++)
        {
            result[i].Set(sh[i,3], sh[i, 1], sh[i,2], sh[i, 0]- sh[i, 6]);
        }
        for (int i1 = 0; i1 < 3; i1++)
        {
            result[3+i1].Set(sh[i1, 4], sh[i1, 5], sh[i1, 6]*3.0f, sh[i1,7]);
        }
        result[6].Set(sh[0, 8], sh[1, 8], sh[2,8],1.0f);
    }
    public void SetUniforms()
    {
     
       
        material.SetVector(sourceSizeUniformID, HiZBufferRenderPass.hiZTargetMip0SourceSize);

        var sh = RenderSettings.ambientProbe;
        Vector4[] SHVals = new Vector4[7];
        GetSHVectorArrays(SHVals, ref sh);

        material.SetVectorArray(ssrAmbientSHUniformID, SHVals);
        material.SetFloat(ssrMinSmoothnessUniformID,settings.ssrMinSmoothness);
        material.SetInt(maxIterationsUniformID,settings.maxIterations);
        material.SetInt(maxHiZMipLevelUniformID,HiZBufferRenderPass.maxHiZMipLevel);
        material.SetFloat(ssrThicknessUniformID,settings.ssrThickness);
        material.SetFloat(maxTracingDistanceUniformID, settings.maxTracingDistance);
        material.SetFloat(ssrBlendFactorUniformID,settings.ssrBlendFactor);
        if (settings.glossyReflectionSimulatingMethod == GlossyReflectionSimulatingMethod.ColorPyramid)
        {
            material.SetInteger(useColorPyramidUniformID, 1);
            material.SetInteger(useTemporalFilterUniformID, 0);
            material.SetInteger(useNormalImportanceSamplingUniformID, 0);
        }
        else
        {
            material.SetInteger(useColorPyramidUniformID, 0);
            material.SetInteger(useTemporalFilterUniformID, 1);
            material.SetInteger(useNormalImportanceSamplingUniformID, 1);
        }
        
      //  material.SetFloat(maxColorPyramidMipLevelUniformID,ColorPyramidRenderPass.maxColorPyramidMipLevel-1);

      
   
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (material == null)
        {
           
            return;
        }

        if (ssrRenderTarget.rt == null)
        {
            Debug.Log("render target null");
            return;
        }
        SetUniforms();
        var cmd = CommandBufferPool.Get("Screen Space Reflections");

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        
        var sourceTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
        if (sourceTexture == null || sourceTexture.rt == null)
        {
            Debug.Log("camera color texture null");
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
            return;
        }
      
        Blit(cmd, sourceTexture, tmpCameraColorTarget);
  
        material.SetTexture(cameraColorTexUniformID, tmpCameraColorTarget);
        Blit(cmd, sourceTexture, ssrRenderTarget, material, 0);

        material.SetTexture(ssrResultTexUniformID, ssrRenderTarget);
        material.SetTexture(prevSSRBlendResultUniformID, prevSSRBlendTarget);
        Blit(cmd, ssrRenderTarget, ssrBlendTarget,material,1);
        Blit(cmd, ssrBlendTarget, prevSSRBlendTarget);

        Blit(cmd, ssrBlendTarget, sourceTexture, material, 2);
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }


    public class SSRRenderPassData
    {
            public Material material;
            public TextureHandle ssrRenderTarget;
            public TextureHandle prevSSRBlendTarget;
            public TextureHandle ssrBlendTarget;
            public TextureHandle tmpCameraColorTarget;
            public TextureHandle cameraSourceTextureHandle;
            public TextureHandle cameraNormalsTextureHandle;
            public TextureHandle gBuffer0;
            public TextureHandle gBuffer1;
        }

    public void SetupCameraParameters(ref UniversalCameraData cameraData)
    {

        Matrix4x4 view = cameraData.GetViewMatrix();
        Matrix4x4 proj = cameraData.GetProjectionMatrix();
        Matrix4x4 vp = proj * view;


        Matrix4x4 cview = view;

        cview.SetColumn(3, new Vector4(0.0f, 0.0f, 0.0f, 1.0f));
        Matrix4x4 cviewProj = proj * cview;

        Matrix4x4 cviewProjInv = cviewProj.inverse;


        var near = cameraData.camera.nearClipPlane;

        Vector4 topLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, 1.0f, -1.0f, 1.0f));
        Vector4 topRightCorner = cviewProjInv.MultiplyPoint(new Vector4(1.0f, 1.0f, -1.0f, 1.0f));
        Vector4 bottomLeftCorner = cviewProjInv.MultiplyPoint(new Vector4(-1.0f, -1.0f, -1.0f, 1.0f));


        Vector4 cameraXExtent = topRightCorner - topLeftCorner;
        Vector4 cameraYExtent = bottomLeftCorner - topLeftCorner;

        near =cameraData.camera.nearClipPlane;



        material.SetVector(cameraViewTopLeftCornerUniformID, topLeftCorner);
        material.SetVector(cameraViewXExtentUniformID, cameraXExtent);
        material.SetVector(cameraViewYExtentUniformID, cameraYExtent);
        material.SetVector(projectionParams2UniformID, new Vector4(1.0f / near,cameraData.worldSpaceCameraPos.x, cameraData.worldSpaceCameraPos.y, cameraData.worldSpaceCameraPos.z));


        }
        public void CreateRenderTextureHandles(RenderGraph renderGraph, UniversalResourceData resourceData,
        UniversalCameraData cameraData, out TextureHandle ssrRenderTarget, out TextureHandle prevSSRBlendTarget,out TextureHandle ssrBlendTarget, out TextureHandle tmpCameraColorTarget)
        {

            var width = Math.Max((int)Math.Ceiling(Mathf.Log(cameraData.cameraTargetDescriptor.width, 2) - 1.0f), 1);
            var height = Math.Max((int)Math.Ceiling(Mathf.Log(cameraData.cameraTargetDescriptor.height, 2) - 1.0f), 1);
            if (HiZBufferRenderPass.downSample == false)
            {
                width = 2 << width;
                height = 2 << height;
            }
            else
            {
                width = 1 << width;
                height = 1 << height;
            }

            ssrRenderTextureDescriptor.width = width;
            ssrRenderTextureDescriptor.height = height;

            tmpCameraColorTextureDescriptor.width = width;
            tmpCameraColorTextureDescriptor.height = height;
            ssrBlendTextureDescriptor.width = width;
            ssrBlendTextureDescriptor.height = height;
            TextureDesc ssrRenderTextureDesc=new TextureDesc(ssrRenderTextureDescriptor);
            TextureDesc tmpCameraColorTextureDesc = new TextureDesc(tmpCameraColorTextureDescriptor);

            TextureDesc ssrBlendTextureDesc = new TextureDesc(ssrBlendTextureDescriptor);
            ssrRenderTarget = renderGraph.CreateTexture(in ssrRenderTextureDesc);
            ssrBlendTarget = renderGraph.CreateTexture(in ssrBlendTextureDesc);
            RenderingUtils.ReAllocateHandleIfNeeded(ref this.prevSSRBlendTarget, ssrBlendTextureDescriptor);
            prevSSRBlendTarget = renderGraph.ImportTexture(this.prevSSRBlendTarget);
            tmpCameraColorTarget = renderGraph.CreateTexture(in tmpCameraColorTextureDesc);
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            SetupCameraParameters(ref cameraData);
            SetUniforms();
            CreateRenderTextureHandles(renderGraph, resourceData, cameraData, out TextureHandle ssrRenderTarget1,
                out TextureHandle prevSSRBlendTarget1, out TextureHandle ssrBlendTarget1, out TextureHandle tmpCameraColorTarget1);

          //  TextureHandle cameraDepthTexture = resourceData.cameraDepthTexture;
            TextureHandle cameraNormalsTexture = resourceData.cameraNormalsTexture;

            if (cameraNormalsTexture.IsValid() == false)
            {
                return;
            }

            TextureHandle cameraColorTexture = resourceData.activeColorTexture;

                if (cameraColorTexture.IsValid() == false)
                {
                    return;
                }
            TextureHandle gBuffer0 = resourceData.gBuffer.Length>1? resourceData.gBuffer[0]: cameraColorTexture;
            TextureHandle gBuffer1 = resourceData.gBuffer.Length > 2? resourceData.gBuffer[1] : TextureHandle.nullHandle;


            if (gBuffer1.IsValid() == false|| gBuffer0.IsValid()==false)
            {
                return;
            }
            using (var builder = renderGraph.AddUnsafePass<SSRRenderPassData>("Screen Space Reflections", out var passData))
            {

                builder.AllowGlobalStateModification(true);
                builder.AllowPassCulling(false);
                passData.material = material;
                passData.prevSSRBlendTarget = prevSSRBlendTarget1;
                passData.ssrBlendTarget = ssrBlendTarget1;
                passData.tmpCameraColorTarget= tmpCameraColorTarget1;
                passData.ssrRenderTarget = ssrRenderTarget1;
                passData.cameraSourceTextureHandle = cameraColorTexture;
                passData.cameraNormalsTextureHandle = cameraNormalsTexture;
                passData.gBuffer0=gBuffer0;
                passData.gBuffer1=gBuffer1;
                builder.UseTexture(prevSSRBlendTarget1, AccessFlags.ReadWrite);
                builder.UseTexture(ssrBlendTarget1, AccessFlags.ReadWrite);
                builder.UseTexture(tmpCameraColorTarget1, AccessFlags.ReadWrite);
                builder.UseTexture(ssrRenderTarget1, AccessFlags.ReadWrite);


                if (cameraNormalsTexture.IsValid() == true)
                {
                    builder.UseTexture(cameraNormalsTexture, AccessFlags.Read);
                }
                


                if (gBuffer0.IsValid() == true)
                {
                    builder.UseTexture(gBuffer0, AccessFlags.Read);
                }
          
                if (gBuffer1.IsValid() == true)
                {
                    builder.UseTexture(gBuffer1, AccessFlags.Read);
                }
               
                if (cameraColorTexture.IsValid() == true)
                {
                    builder.UseTexture(cameraColorTexture, AccessFlags.Read);

                }
                

                builder.SetRenderFunc((SSRRenderPassData data, UnsafeGraphContext rgContext) =>
                {
                    data.material.SetTexture("_CameraNormalsTexture", data.cameraNormalsTextureHandle);
                    data.material.SetTexture("_GBuffer0", data.gBuffer0);
                    data.material.SetTexture("_GBuffer1", data.gBuffer1);
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(rgContext.cmd);
                    Blitter.BlitCameraTexture(cmd,data.cameraSourceTextureHandle,data.tmpCameraColorTarget);
                    data.material.SetTexture(cameraColorTexUniformID, data.tmpCameraColorTarget);
                    Blitter.BlitCameraTexture(cmd, data.tmpCameraColorTarget, data.ssrRenderTarget,data.material, 0);



                    data.material.SetTexture(ssrResultTexUniformID, data.ssrRenderTarget);
                    data.material.SetTexture(prevSSRBlendResultUniformID, data.prevSSRBlendTarget);
                    Blitter.BlitCameraTexture(cmd, data.ssrRenderTarget, data.ssrBlendTarget, data.material, 1);
                    Blitter.BlitCameraTexture(cmd, data.ssrBlendTarget, data.prevSSRBlendTarget);

                    Blitter.BlitCameraTexture(cmd, data.ssrBlendTarget, data.cameraSourceTextureHandle, data.material, 2);
                });

            }

        }

        public void Dispose()
    {
   
        if (ssrRenderTarget != null) ssrRenderTarget.Release();
        if(tmpCameraColorTarget!=null) tmpCameraColorTarget.Release();
        if (prevSSRBlendTarget != null) prevSSRBlendTarget.Release();
        if (ssrBlendTarget != null) ssrBlendTarget.Release();
    }
}

public enum GlossyReflectionSimulatingMethod
{
    ColorPyramid=0,
    PhysicallyBased=1
}
[Serializable]
public class SSRRenderFeatureSettings
{
    [Tooltip(
        "Defines is the SSR render feature using forward rendering mode. In forward rendering mode the render feature cannot fetch PBR material data and use constant data values to calculate reflections.\r\n" +
        "You may ask: Why we use a toggle to switch that instead of automatically detect the rendering mode of current renderer in the code? The answer is that we ACTUALLY CANNOT detect the rendering mode.")]
    public bool isUsingForwardRendering=false;
    
    /// <summary>
    /// Determines what method is used to simulate glossy reflections.
    /// </summary>
   [Tooltip("Determines what method is used to simulate glossy reflections.\r\nColor Pyramid: Samples blurred scene color generated by the Color Pyramid render feature on glossy surfaces as the reflection result.\r\n" +
            "Physically Based: Use importance sampling to generate rays with random directions,trace these rays and use temporal filter to reduce noise. More physically correct than the Color Pyramid method.")]
    public GlossyReflectionSimulatingMethod glossyReflectionSimulatingMethod;
    /// <summary>
    /// Max iterations count of the reflection algorithm.
    /// Higher value results to longer reflection distance. High performance impact.
    /// </summary>
    [Tooltip("Max iterations count of the reflection algorithm.\r\nHigher value results to longer reflection distance. High performance impact.")]
    [Range(8, 1024)]
 
    public int maxIterations;
   
    [Tooltip("The \"object thickness\" value used in ray intersecting progress.\r\nTune this value according to the scene to reduce artifacts.")]
    [Range(0.01f, 2f)]
    public float ssrThickness;
   
    [Tooltip("The max tracing distance of the ray. Currently not functional.")]
    [Range(10f, 1000f)]
    public float maxTracingDistance;
    
    [Tooltip("A blending factor to mix the reflection result with the rendered image.")]
    [Range(0f, 1f)]
    public float ssrBlendFactor=0.8f;

    [Tooltip("The minimum material smoothness required to trace a reflection ray.\r\nA surface with lower smoothness than this value will not receive reflections.")]
    [Range(0f,1f)]
    public float ssrMinSmoothness = 0.8f;
}
}
