using Godot;

/// <summary>
/// Builds the 5-pass black hole render pipeline using SubViewports.
/// Buffer A → B → C → D → Final (on-screen).
/// Textures are bound once via ViewportTexture (auto-updating, no per-frame copies).
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

        // Load shaders
        var shA = GD.Load<Shader>("res://shaders/buffer_a.gdshader");
        var shB = GD.Load<Shader>("res://shaders/buffer_b.gdshader");
        var shC = GD.Load<Shader>("res://shaders/buffer_c.gdshader");
        var shD = GD.Load<Shader>("res://shaders/buffer_d.gdshader");
        var shF = GD.Load<Shader>("res://shaders/image_final.gdshader");

        // Build SubViewport chain
        _svA = MakeSubViewport(sizeI);
        _rectA = MakeRect(shA);
        _svA.AddChild(_rectA);
        AddChild(_svA);

        _svB = MakeSubViewport(sizeI);
        _svB.AddChild(MakeRect(shB));
        AddChild(_svB);

        _svC = MakeSubViewport(sizeI);
        _svC.AddChild(MakeRect(shC));
        AddChild(_svC);

        _svD = MakeSubViewport(sizeI);
        _svD.AddChild(MakeRect(shD));
        AddChild(_svD);

        // Final on-screen rect
        _rectFinal = MakeRect(shF);
        _rectFinal.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(_rectFinal);

        // --- Wire textures (one-time bind, ViewportTexture auto-updates) ---
        _matA = (ShaderMaterial)_rectA.Material;
        _matA.SetShaderParameter("noise_tex", _noiseTex);
        _matA.SetShaderParameter("disc_tex", _discTex);
        _matA.SetShaderParameter("resolution", size);
        _matA.SetShaderParameter("mouse_pos", new Vector2(0.35f, 0.5f));

        // B reads A
        var matB = GetMat(_svB);
        matB.SetShaderParameter("source_tex", _svA.GetTexture());
        matB.SetShaderParameter("resolution", size);

        // C reads B
        var matC = GetMat(_svC);
        matC.SetShaderParameter("source_tex", _svB.GetTexture());
        matC.SetShaderParameter("resolution", size);

        // D reads C
        var matD = GetMat(_svD);
        matD.SetShaderParameter("source_tex", _svC.GetTexture());
        matD.SetShaderParameter("resolution", size);

        // Final reads A + D
        var matF = (ShaderMaterial)_rectFinal.Material;
        matF.SetShaderParameter("buffer_a_tex", _svA.GetTexture());
        matF.SetShaderParameter("bloom_tex", _svD.GetTexture());
        matF.SetShaderParameter("resolution", size);

        // Listen for window resize
        GetTree().Root.SizeChanged += OnResize;
    }

    private void OnResize()
    {
        var size = GetViewportRect().Size;
        var sizeI = new Vector2I((int)size.X, (int)size.Y);

        _svA.Size = sizeI;
        _svB.Size = sizeI;
        _svC.Size = sizeI;
        _svD.Size = sizeI;

        // Update resolution uniforms
        _matA.SetShaderParameter("resolution", size);
        GetMat(_svB).SetShaderParameter("resolution", size);
        GetMat(_svC).SetShaderParameter("resolution", size);
        GetMat(_svD).SetShaderParameter("resolution", size);
        ((ShaderMaterial)_rectFinal.Material).SetShaderParameter("resolution", size);
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
        {
            _matA.SetShaderParameter("mouse_pressed", mb.Pressed);
        }
    }

    // --- Helpers ---

    private void CreateTextures()
    {
        // 256×256 random noise (replaces Shadertoy's gray noise channel)
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

    private static SubViewport MakeSubViewport(Vector2I size)
    {
        return new SubViewport
        {
            Size = size,
            RenderTargetUpdateMode = SubViewport.UpdateMode.Always,
            TransparentBg = false,
            HandleInputLocally = false,
        };
    }

    private static ColorRect MakeRect(Shader shader)
    {
        var r = new ColorRect();
        r.SetAnchorsPreset(LayoutPreset.FullRect);
        r.Material = new ShaderMaterial { Shader = shader };
        return r;
    }

    private static ShaderMaterial GetMat(SubViewport sv)
    {
        return (ShaderMaterial)sv.GetChild<ColorRect>(0).Material;
    }
}
