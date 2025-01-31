using System;
using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;
using static UnityEngine.XR.XRDisplaySubsystem;
using static UnityScreenSpaceReflections.HiZBufferRenderPass;
using Object = UnityEngine.Object;

namespace UnityScreenSpaceReflections
{
    public class ColorPyramidRenderFeatrue :ScriptableRendererFeature
    {
        [SerializeField] private ColorPyramidRenderFeatureSettings settings;
        private Shader shader;
        private Material material;
        private ColorPyramidRenderPass colorPyramidRenderPass;
        public override void Create()
        {
        //    Debug.Log("validate");
            shader = Shader.Find("Hidden/ColorPyramidShader");
            if (shader == null)
            {
                Debug.Log("null shader");
                return;
            }

            material = CoreUtils.CreateEngineMaterial(shader);
            if (settings == null)
            {
                settings=new ColorPyramidRenderFeatureSettings();
            }
            if (colorPyramidRenderPass != null)
            {
                Debug.Log("dispose colorPyramid");
                colorPyramidRenderPass.Dispose();
            }
            colorPyramidRenderPass = new ColorPyramidRenderPass(material, settings);
            

            colorPyramidRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            
            renderer.EnqueuePass(colorPyramidRenderPass);
        }
        protected override void Dispose(bool disposing)
        {
            colorPyramidRenderPass.Dispose();
            CoreUtils.Destroy(material);
        }
    }
    [Serializable]
    public class ColorPyramidRenderFeatureSettings
    {
        [Tooltip("The total color mipmap chain count of the Color Pyramid.")]
        [Range(2, 16)] public int colorPyramidMipCount=3;
       
    }
    [ExecuteAlways]
    public class ColorPyramidRenderPass : ScriptableRenderPass
    {
        private ColorPyramidRenderFeatureSettings defaultSettings;
        private Material material;
        private RTHandle[] renderTargetMips;
        private RenderTextureDescriptor[] renderTargetMipDescriptors;
        private RenderTextureDescriptor finalColorPyramidTextureDescriptor;
        private RTHandle finalColorPyramidTarget;
        private int sourceSizeUniformID;
        private int colorPyramidTextureID;
        private int maxColorPyramidMipLevelID;
        private int actualMaxMipCount;
        public static int maxColorPyramidMipLevel;
        public static Vector4 colorPyramidTargetMip0SourceSize;
        public ColorPyramidRenderPass(Material mat, ColorPyramidRenderFeatureSettings defaultSettings)
        {
            this.defaultSettings=defaultSettings;
            this.material = mat;
            renderTargetMips = new RTHandle[defaultSettings.colorPyramidMipCount];
            renderTargetMipDescriptors = new RenderTextureDescriptor[defaultSettings.colorPyramidMipCount];
            sourceSizeUniformID = Shader.PropertyToID("SourceSize");
            colorPyramidTextureID = Shader.PropertyToID("ColorPyramidTexture");
            maxColorPyramidMipLevelID = Shader.PropertyToID("MaxColorPyramidMipLevel");
            
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            if (defaultSettings.colorPyramidMipCount <= 0)
            {
                Debug.Log("color pyramid level is 0");
                return;
            }
            var desc = cameraTextureDescriptor;
            var width = Math.Max((int)Math.Ceiling(Mathf.Log(desc.width, 2) - 1.0f), 1);
            var height = Math.Max((int)Math.Ceiling(Mathf.Log(desc.height, 2) - 1.0f), 1);
            width = 2 << width;
            height = 2 << height;
            int minLength = Math.Min(width, height);

            int maxMipLevel = (int)Math.Ceiling(Mathf.Log(desc.height, 2));
            actualMaxMipCount = Math.Min(maxMipLevel, defaultSettings.colorPyramidMipCount);
            finalColorPyramidTextureDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.Default, 0,
                actualMaxMipCount);
            finalColorPyramidTextureDescriptor.useMipMap = true;
            finalColorPyramidTextureDescriptor.sRGB = true;
            colorPyramidTargetMip0SourceSize = new Vector4(width, height, 1.0f / width, 1.0f / height);
            RenderingUtils.ReAllocateIfNeeded(ref finalColorPyramidTarget, in finalColorPyramidTextureDescriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "finalColorPyramidTarget");
            for (int i = 0; i < actualMaxMipCount; i++)
            {
                renderTargetMipDescriptors[i] = new RenderTextureDescriptor(width, height, RenderTextureFormat.Default, 0, 1);
                renderTargetMipDescriptors[i].msaaSamples = 1;
                renderTargetMipDescriptors[i].useMipMap = false;
                renderTargetMipDescriptors[i].sRGB = true;
                RenderingUtils.ReAllocateIfNeeded(ref renderTargetMips[i], renderTargetMipDescriptors[i], FilterMode.Point, TextureWrapMode.Clamp, name: "colorPyramidTarget" + i);


                width = Math.Max(width / 2, 1);
                height = Math.Max(height / 2, 1);
            }

        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {



           


            if (material == null)
            {
                Debug.LogErrorFormat("{0}.Execute(): Missing material.", GetType().Name);
                return;
            }

            if (defaultSettings.colorPyramidMipCount <= 0)
            {
                Debug.Log("color pyramid mip count is 0");
                return;
            }
            var cmd = CommandBufferPool.Get("Generate Color Pyramid");
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

         
                var cameraColorTexture = renderingData.cameraData.renderer.cameraColorTargetHandle;
                if (cameraColorTexture == null || cameraColorTexture.rt == null)
                {
                    Debug.Log("camera color target null");
                    context.ExecuteCommandBuffer(cmd);
                    CommandBufferPool.Release(cmd);
                return;

                }


            // mip 0
             cmd.Blit( cameraColorTexture,renderTargetMips[0]);
                cmd.CopyTexture(renderTargetMips[0], 0, 0, finalColorPyramidTarget, 0, 0);
            
                // mip 1~max
                for (int i = 1; i < actualMaxMipCount; i++)
                {
           //       Debug.Log("hiz mip count:"+defaultSettings.hiZMipCount+" final hiz target mip count:"+ finalHiZTarget.rt.mipmapCount+" actual hiz target max mip count:"+ actualMaxMipCount);
                    cmd.SetGlobalVector(sourceSizeUniformID, new Vector4(renderTargetMipDescriptors[i - 1].width, renderTargetMipDescriptors[i - 1].height, 1.0f / renderTargetMipDescriptors[i - 1].width, 1.0f / renderTargetMipDescriptors[i - 1].height));
                    Blitter.BlitCameraTexture(cmd, renderTargetMips[i - 1], renderTargetMips[i], material, 0);

                    cmd.CopyTexture(renderTargetMips[i], 0, 0, finalColorPyramidTarget, 0, i);
                }

                maxColorPyramidMipLevel = actualMaxMipCount;
               
                // set global hiz texture
                cmd.SetGlobalFloat(maxColorPyramidMipLevelID, actualMaxMipCount - 1);
                cmd.SetGlobalTexture(colorPyramidTextureID, finalColorPyramidTarget);
             //   Blitter.BlitCameraTexture(cmd, finalHiZTarget, cameraColorTexture);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
        public class ColorPyramidBufferPassData
        {
            public Material material;
            public TextureHandle[] renderTargetMips;
            public TextureHandle finalColorPyramidTarget;
            public TextureHandle cameraColorTexture;

        }

        public void CreateRenderTextureHandles(RenderGraph renderGraph, UniversalResourceData resourceData,
            UniversalCameraData cameraData, out TextureHandle[] renderTargetMips, out TextureHandle finalColorPyramidTarget)
        {

            var desc = cameraData.cameraTargetDescriptor;
            var width = Math.Max((int)Math.Ceiling(Mathf.Log(desc.width, 2) - 1.0f), 1);
            var height = Math.Max((int)Math.Ceiling(Mathf.Log(desc.height, 2) - 1.0f), 1);
       
           
                width = 2 << width;
                height = 2 << height;
            
            int minLength = Math.Min(width, height);

            int maxMipLevel = (int)Math.Ceiling(Mathf.Log(desc.height, 2));
            actualMaxMipCount = Math.Min(maxMipLevel, defaultSettings.colorPyramidMipCount);
            //   Debug.Log(actualMaxMipCount);
            renderTargetMips = new TextureHandle[actualMaxMipCount + 1];
            finalColorPyramidTextureDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.Default, 0, actualMaxMipCount
            );

            finalColorPyramidTextureDescriptor.useMipMap = true;
            finalColorPyramidTextureDescriptor.sRGB = false;

            colorPyramidTargetMip0SourceSize = new Vector4(width, height, 1.0f / width, 1.0f / height);
            TextureDesc finalColorPyramidTargetDesc = new TextureDesc(finalColorPyramidTextureDescriptor);

            finalColorPyramidTarget = renderGraph.CreateTexture(in finalColorPyramidTargetDesc);

            for (int i = 0; i < actualMaxMipCount; i++)
            {
                renderTargetMipDescriptors[i] = new RenderTextureDescriptor(width, height, RenderTextureFormat.Default, 0, 1);
                renderTargetMipDescriptors[i].msaaSamples = 1;
                renderTargetMipDescriptors[i].useMipMap = false;
                renderTargetMipDescriptors[i].sRGB = false;
                renderTargetMips[i] = UniversalRenderer.CreateRenderGraphTexture(renderGraph, renderTargetMipDescriptors[i], "ColorPyramidBufferTargetMip" + i, true, FilterMode.Point, TextureWrapMode.Clamp);


                width = Math.Max(width / 2, 1);
                height = Math.Max(height / 2, 1);
            }

        }




        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            CreateRenderTextureHandles(renderGraph, resourceData, cameraData, out TextureHandle[] renderTargetMips1, out TextureHandle finalHiZTarget1);



            TextureHandle cameraDepthTexture = resourceData.cameraDepthTexture;
            TextureHandle cameraNormalsTexture = resourceData.cameraNormalsTexture;
            TextureHandle cameraColorTexture = resourceData.activeColorTexture;
            using (var builder = renderGraph.AddUnsafePass<ColorPyramidBufferPassData>("Generate Color Pyramid Buffer", out var passData))
            {

                builder.AllowGlobalStateModification(true);
                builder.AllowPassCulling(false);

                passData.material = material;
                passData.cameraColorTexture = cameraColorTexture;
                passData.renderTargetMips = renderTargetMips1;
                passData.finalColorPyramidTarget = finalHiZTarget1;

                if (cameraDepthTexture.IsValid() == true)
                {
                    builder.UseTexture(cameraDepthTexture, AccessFlags.ReadWrite);

                }
                if (cameraColorTexture.IsValid() == true)
                {
                    builder.UseTexture(cameraColorTexture, AccessFlags.ReadWrite);

                }
                foreach (var texture in renderTargetMips1)
                {
                    if (texture.IsValid() == true)
                    {
                        builder.UseTexture(texture, AccessFlags.ReadWrite);
                    }

                }
                if (finalHiZTarget1.IsValid() == true)
                {
                    builder.UseTexture(finalHiZTarget1, AccessFlags.ReadWrite);
                }

                builder.SetRenderFunc((ColorPyramidBufferPassData data, UnsafeGraphContext rgContext) =>
                {
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(rgContext.cmd);
                    Blitter.BlitCameraTexture(cmd, data.cameraColorTexture, data.renderTargetMips[0]);



                    cmd.CopyTexture(data.renderTargetMips[0], 0, 0, data.finalColorPyramidTarget, 0, 0);

                    for (int i = 1; i < actualMaxMipCount; i++)
                    {
                        //       Debug.Log("hiz mip count:"+defaultSettings.hiZMipCount+" final hiz target mip count:"+ finalHiZTarget.rt.mipmapCount+" actual hiz target max mip count:"+ actualMaxMipCount);
                        cmd.SetGlobalVector(sourceSizeUniformID, new Vector4(renderTargetMipDescriptors[i - 1].width, renderTargetMipDescriptors[i - 1].height, 1.0f / renderTargetMipDescriptors[i - 1].width, 1.0f / renderTargetMipDescriptors[i - 1].height));
                        Blitter.BlitCameraTexture(cmd, data.renderTargetMips[i - 1], data.renderTargetMips[i], material, 0);
                        //    Blitter.BlitCameraTexture(cmd, data.renderTargetMips[i], data.finalHiZTarget,i,false);
                        cmd.CopyTexture(data.renderTargetMips[i], 0, 0, data.finalColorPyramidTarget, 0, i);
                    }
                    maxHiZMipLevel = actualMaxMipCount;
                    // set global hiz texture
                    cmd.SetGlobalFloat(maxColorPyramidMipLevelID, actualMaxMipCount - 1);
                    cmd.SetGlobalTexture(colorPyramidTextureID, data.finalColorPyramidTarget);

                });
            }
        }

        public void Dispose()
        {
         

                        if (finalColorPyramidTarget != null) finalColorPyramidTarget.Release();
                        if (renderTargetMips != null)
                        {
                            foreach (var item in renderTargetMips)
                            {
                                if (item != null)
                                {
                                    item.Release();
                                }
                            }
                        }
        }
    }
}