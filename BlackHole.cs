using Godot;

/// <summary>
/// Black Hole 5-pass pipeline with ping-pong temporal AA.
/// Two SubViewports for Buffer A alternate each frame (ping-pong).
/// The inactive one's texture is used as prev_frame for temporal blending.
/// No GetImage() calls — everything stays on GPU.
/// </summary>
public partial class BlackHole : Control
{
    // Ping-pong pair for Buffer A (temporal AA)
    private SubViewport _svA0, _svA1;
    private ColorRect _rectA0, _rectA1;
    private ShaderMaterial _matA0, _matA1;
    private bool _pingPong; // false = A0 active, true = A1 active

    // Bloom chain
    private SubViewport _svB, _svC, _svD;
    private ColorRect _rectFinal;

    // Textures
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

        // --- Ping-pong A0 and A1 ---
        _svA0 = MakeSV(sizeI);
        _rectA0 = MakeRect(shA);
        _svA0.AddChild(_rectA0);
        AddChild(_svA0);

        _svA1 = MakeSV(sizeI);
        _rectA1 = MakeRect(shA);
        _svA1.AddChild(_rectA1);
        AddChild(_svA1);

        _matA0 = (ShaderMaterial)_rectA0.Material;
        _matA1 = (ShaderMaterial)_rectA1.Material;

        // Set shared uniforms on both
        foreach (var mat in new[] { _matA0, _matA1 })
        {
            mat.SetShaderParameter("noise_tex", _noiseTex);
            mat.SetShaderParameter("disc_tex", _discTex);
            mat.SetShaderParameter("resolution", size);
            mat.SetShaderParameter("mouse_pos", new Vector2(0.35f, 0.5f));
        }

        // Cross-wire: A0 reads A1's texture as prev_frame, and vice versa
        _matA0.SetShaderParameter("prev_frame", _svA1.GetTexture());
        _matA1.SetShaderParameter("prev_frame", _svA0.GetTexture());

        // Start with A0 active, A1 disabled (provides black prev_frame)
        _svA0.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
        _svA1.RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled;
        _pingPong = false;

        // --- Bloom chain B → C → D ---
        _svB = MakeSV(sizeI);
        _svB.AddChild(MakeRect(shB));
        AddChild(_svB);

        _svC = MakeSV(sizeI);
        _svC.AddChild(MakeRect(shC));
        AddChild(_svC);

        _svD = MakeSV(sizeI);
        _svD.AddChild(MakeRect(shD));
        AddChild(_svD);

        // --- Final on-screen ---
        _rectFinal = MakeRect(shF);
        _rectFinal.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(_rectFinal);

        // Wire bloom chain (initially reads from A0)
        WireBloomChain(size);

        GetTree().Root.SizeChanged += OnResize;
    }

    private void WireBloomChain(Vector2 size)
    {
        var activeSV = _pingPong ? _svA1 : _svA0;

        GetMat(_svB).SetShaderParameter("source_tex", activeSV.GetTexture());
        GetMat(_svB).SetShaderParameter("resolution", size);

        GetMat(_svC).SetShaderParameter("source_tex", _svB.GetTexture());
        GetMat(_svC).SetShaderParameter("resolution", size);

        GetMat(_svD).SetShaderParameter("source_tex", _svC.GetTexture());
        GetMat(_svD).SetShaderParameter("resolution", size);

        var matF = (ShaderMaterial)_rectFinal.Material;
        matF.SetShaderParameter("buffer_a_tex", activeSV.GetTexture());
        matF.SetShaderParameter("bloom_tex", _svD.GetTexture());
        matF.SetShaderParameter("resolution", size);
    }

    public override void _Process(double delta)
    {
        // Ping-pong: swap which SubViewport renders
        _pingPong = !_pingPong;

        if (_pingPong)
        {
            _svA1.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
            _svA0.RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled;
        }
        else
        {
            _svA0.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
            _svA1.RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled;
        }

        // Update bloom chain to read from the now-active buffer
        var activeSV = _pingPong ? _svA1 : _svA0;
        GetMat(_svB).SetShaderParameter("source_tex", activeSV.GetTexture());
        ((ShaderMaterial)_rectFinal.Material).SetShaderParameter("buffer_a_tex", activeSV.GetTexture());
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseMotion mm)
        {
            var s = GetViewportRect().Size;
            var pos = new Vector2(mm.Position.X / s.X, 1f - mm.Position.Y / s.Y);
            _matA0.SetShaderParameter("mouse_pos", pos);
            _matA1.SetShaderParameter("mouse_pos", pos);
        }
        if (@event is InputEventMouseButton mb)
        {
            _matA0.SetShaderParameter("mouse_pressed", mb.Pressed);
            _matA1.SetShaderParameter("mouse_pressed", mb.Pressed);
        }
    }

    private void OnResize()
    {
        var size = GetViewportRect().Size;
        var sizeI = new Vector2I((int)size.X, (int)size.Y);
        _svA0.Size = sizeI; _svA1.Size = sizeI;
        _svB.Size = sizeI; _svC.Size = sizeI; _svD.Size = sizeI;
        _matA0.SetShaderParameter("resolution", size);
        _matA1.SetShaderParameter("resolution", size);
        WireBloomChain(size);
    }

    private void CreateTextures()
    {
        var img = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        var rng = new RandomNumberGenerator { Seed = 42 };
        for (int y = 0; y < 256; y++)
            for (int x = 0; x < 256; x++)
                img.SetPixel(x, y, new Color(rng.Randf(), rng.Randf(), rng.Randf(), rng.Randf()));
        _noiseTex = ImageTexture.CreateFromImage(img);

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

    private static SubViewport MakeSV(Vector2I size) => new()
    {
        Size = size,
        RenderTargetUpdateMode = SubViewport.UpdateMode.Always,
        TransparentBg = false,
        HandleInputLocally = false,
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
