using Godot;

/// <summary>
/// Black Hole 5-pass pipeline with HDR 2D SubViewports.
/// Key insight: SubViewports default to LDR 8-bit sRGB for 2D rendering.
/// Buffer A outputs tiny values (0.0001 range) that get destroyed by 8-bit quantization.
/// Setting UseHdr2D = true enables RGBA16 float format, preserving precision.
/// </summary>
public partial class BlackHole : Control
{
    private SubViewport _svA, _svB, _svC, _svD;
    private ColorRect _rectA, _rectFinal;
    private ShaderMaterial _matA;
    private ImageTexture _noiseTex;
    private NoiseTexture2D _discTex;

    public override void _Ready()
    {
        CreateTextures();

        var size = GetViewportRect().Size;
        var sizeI = new Vector2I((int)size.X, (int)size.Y);

        var shA = GD.Load<Shader>("res://shaders/buffer_a.gdshader");
        var shB = GD.Load<Shader>("res://shaders/buffer_b.gdshader");
        var shC = GD.Load<Shader>("res://shaders/buffer_c.gdshader");
        var shD = GD.Load<Shader>("res://shaders/buffer_d.gdshader");
        var shF = GD.Load<Shader>("res://shaders/image_final.gdshader");

        // Buffer A — main render
        _svA = MakeSV(sizeI);
        _rectA = MakeRect(shA);
        _svA.AddChild(_rectA);
        AddChild(_svA);

        _matA = (ShaderMaterial)_rectA.Material;
        _matA.SetShaderParameter("noise_tex", _noiseTex);
        _matA.SetShaderParameter("disc_tex", _discTex);
        _matA.SetShaderParameter("resolution", size);
        _matA.SetShaderParameter("mouse_pos", new Vector2(0.35f, 0.5f));

        // Bloom chain: B → C → D
        _svB = MakeSV(sizeI);
        _svB.AddChild(MakeRect(shB));
        AddChild(_svB);

        _svC = MakeSV(sizeI);
        _svC.AddChild(MakeRect(shC));
        AddChild(_svC);

        _svD = MakeSV(sizeI);
        _svD.AddChild(MakeRect(shD));
        AddChild(_svD);

        // Final on-screen composite
        _rectFinal = MakeRect(shF);
        _rectFinal.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(_rectFinal);

        // Wire textures (one-time, ViewportTexture auto-updates)
        GetMat(_svB).SetShaderParameter("source_tex", _svA.GetTexture());
        GetMat(_svB).SetShaderParameter("resolution", size);
        GetMat(_svC).SetShaderParameter("source_tex", _svB.GetTexture());
        GetMat(_svC).SetShaderParameter("resolution", size);
        GetMat(_svD).SetShaderParameter("source_tex", _svC.GetTexture());
        GetMat(_svD).SetShaderParameter("resolution", size);

        var matF = (ShaderMaterial)_rectFinal.Material;
        matF.SetShaderParameter("buffer_a_tex", _svA.GetTexture());
        matF.SetShaderParameter("bloom_tex", _svD.GetTexture());
        matF.SetShaderParameter("resolution", size);

        GetTree().Root.SizeChanged += OnResize;
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseMotion mm)
        {
            var s = GetViewportRect().Size;
            _matA.SetShaderParameter("mouse_pos",
                new Vector2(mm.Position.X / s.X, 1f - mm.Position.Y / s.Y));
        }
        if (@event is InputEventMouseButton mb)
            _matA.SetShaderParameter("mouse_pressed", mb.Pressed);
    }

    private void OnResize()
    {
        var size = GetViewportRect().Size;
        var sizeI = new Vector2I((int)size.X, (int)size.Y);
        _svA.Size = sizeI; _svB.Size = sizeI;
        _svC.Size = sizeI; _svD.Size = sizeI;
        _matA.SetShaderParameter("resolution", size);
        GetMat(_svB).SetShaderParameter("resolution", size);
        GetMat(_svC).SetShaderParameter("resolution", size);
        GetMat(_svD).SetShaderParameter("resolution", size);
        ((ShaderMaterial)_rectFinal.Material).SetShaderParameter("resolution", size);
    }

    private void CreateTextures()
    {
        // 256×256 random noise (replaces Shadertoy gray noise channel)
        var img = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        var rng = new RandomNumberGenerator { Seed = 42 };
        for (int y = 0; y < 256; y++)
            for (int x = 0; x < 256; x++)
                img.SetPixel(x, y, new Color(rng.Randf(), rng.Randf(), rng.Randf(), rng.Randf()));
        _noiseTex = ImageTexture.CreateFromImage(img);

        // Simplex noise for accretion disc detail
        _discTex = new NoiseTexture2D
        {
            Width = 512, Height = 512, Seamless = true,
            Noise = new FastNoiseLite
            {
                NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
                Frequency = 0.02f, FractalOctaves = 5
            }
        };
    }

    /// <summary>
    /// Creates an HDR SubViewport with RGBA16 format for 2D rendering.
    /// This is CRITICAL — without UseHdr2D, buffer values are clamped to 8-bit [0,1].
    /// </summary>
    private static SubViewport MakeSV(Vector2I size) => new()
    {
        Size = size,
        RenderTargetUpdateMode = SubViewport.UpdateMode.Always,
        TransparentBg = false,
        HandleInputLocally = false,
        UseHdr2D = true,  // ← THE KEY FIX: RGBA16 float format
    };

    private static ColorRect MakeRect(Shader sh)
    {
        var r = new ColorRect();
        r.SetAnchorsPreset(LayoutPreset.FullRect);
        r.Material = new ShaderMaterial { Shader = sh };
        return r;
    }

    private static ShaderMaterial GetMat(SubViewport sv)
        => (ShaderMaterial)sv.GetChild<ColorRect>(0).Material;
}
