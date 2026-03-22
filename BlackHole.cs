using Godot;

/// <summary>
/// Black Hole multi-pass pipeline controller.
/// Creates SubViewport chain: Buffer A → B → C → D → Final composite.
/// Handles noise texture generation, temporal AA feedback, and mouse input.
/// </summary>
public partial class BlackHole : Control
{
    // SubViewports for each buffer pass
    private SubViewport _svA, _svB, _svC, _svD;
    private ColorRect _rectA, _rectB, _rectC, _rectD, _rectFinal;

    // Shaders
    private Shader _shaderA, _shaderB, _shaderC, _shaderD, _shaderFinal;

    // Textures
    private ImageTexture _noiseTexture;
    private NoiseTexture2D _discTexture;

    // Temporal AA feedback
    private ImageTexture _prevFrameTexture;

    public override void _Ready()
    {
        GenerateNoiseTexture();
        GenerateDiscTexture();
        LoadShaders();
        BuildPipeline();
    }

    private void LoadShaders()
    {
        _shaderA = GD.Load<Shader>("res://shaders/buffer_a.gdshader");
        _shaderB = GD.Load<Shader>("res://shaders/buffer_b.gdshader");
        _shaderC = GD.Load<Shader>("res://shaders/buffer_c.gdshader");
        _shaderD = GD.Load<Shader>("res://shaders/buffer_d.gdshader");
        _shaderFinal = GD.Load<Shader>("res://shaders/image_final.gdshader");
    }

    /// <summary>
    /// Generate a 256x256 random noise texture (equivalent to Shadertoy's gray noise).
    /// </summary>
    private void GenerateNoiseTexture()
    {
        var img = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        var rng = new RandomNumberGenerator();
        rng.Seed = 42; // Fixed seed for consistency

        for (int y = 0; y < 256; y++)
        {
            for (int x = 0; x < 256; x++)
            {
                img.SetPixel(x, y, new Color(
                    rng.Randf(), rng.Randf(), rng.Randf(), rng.Randf()
                ));
            }
        }

        _noiseTexture = ImageTexture.CreateFromImage(img);
    }

    /// <summary>
    /// Generate a noise texture for the accretion disc detail (iChannel1 equivalent).
    /// </summary>
    private void GenerateDiscTexture()
    {
        _discTexture = new NoiseTexture2D();
        var noise = new FastNoiseLite();
        noise.NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex;
        noise.Frequency = 0.02f;
        noise.FractalOctaves = 5;
        noise.FractalLacunarity = 2.0f;
        noise.FractalGain = 0.5f;
        _discTexture.Noise = noise;
        _discTexture.Width = 512;
        _discTexture.Height = 512;
        _discTexture.Seamless = true;
    }

    private void BuildPipeline()
    {
        var viewportSize = GetViewportRect().Size;
        int w = (int)viewportSize.X;
        int h = (int)viewportSize.Y;

        // ---- SubViewport A: Main black hole render ----
        _svA = CreateSubViewport(w, h);
        _rectA = CreateColorRect(_shaderA);
        _svA.AddChild(_rectA);
        AddChild(_svA);

        var matA = (ShaderMaterial)_rectA.Material;
        matA.SetShaderParameter("resolution", viewportSize);
        matA.SetShaderParameter("noise_texture", _noiseTexture);
        matA.SetShaderParameter("disc_texture", _discTexture);

        // Create initial prev_frame texture (black)
        var blackImg = Image.CreateEmpty(w, h, false, Image.Format.Rgba8);
        blackImg.Fill(Colors.Black);
        _prevFrameTexture = ImageTexture.CreateFromImage(blackImg);
        matA.SetShaderParameter("prev_frame", _prevFrameTexture);

        // ---- SubViewport B: Bloom mipmap downsample ----
        _svB = CreateSubViewport(w, h);
        _rectB = CreateColorRect(_shaderB);
        _svB.AddChild(_rectB);
        AddChild(_svB);

        // ---- SubViewport C: Horizontal blur ----
        _svC = CreateSubViewport(w, h);
        _rectC = CreateColorRect(_shaderC);
        _svC.AddChild(_rectC);
        AddChild(_svC);

        // ---- SubViewport D: Vertical blur ----
        _svD = CreateSubViewport(w, h);
        _rectD = CreateColorRect(_shaderD);
        _svD.AddChild(_rectD);
        AddChild(_svD);

        // ---- Final composite (rendered to screen) ----
        _rectFinal = CreateColorRect(_shaderFinal);
        _rectFinal.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(_rectFinal);

        // Wire textures between passes
        WireTextures(viewportSize);
    }

    private void WireTextures(Vector2 viewportSize)
    {
        // B reads A
        var matB = (ShaderMaterial)_rectB.Material;
        matB.SetShaderParameter("source_texture", _svA.GetTexture());
        matB.SetShaderParameter("resolution", viewportSize);

        // C reads B
        var matC = (ShaderMaterial)_rectC.Material;
        matC.SetShaderParameter("source_texture", _svB.GetTexture());
        matC.SetShaderParameter("resolution", viewportSize);

        // D reads C
        var matD = (ShaderMaterial)_rectD.Material;
        matD.SetShaderParameter("source_texture", _svC.GetTexture());
        matD.SetShaderParameter("resolution", viewportSize);

        // Final reads A (raw) + D (bloom)
        var matFinal = (ShaderMaterial)_rectFinal.Material;
        matFinal.SetShaderParameter("buffer_a_texture", _svA.GetTexture());
        matFinal.SetShaderParameter("bloom_texture", _svD.GetTexture());
        matFinal.SetShaderParameter("resolution", viewportSize);
    }

    private SubViewport CreateSubViewport(int w, int h)
    {
        var sv = new SubViewport();
        sv.Size = new Vector2I(w, h);
        sv.RenderTargetUpdateMode = SubViewport.UpdateMode.Always;
        sv.TransparentBg = false;
        sv.HandleInputLocally = false;
        sv.RenderTargetClearMode = SubViewport.ClearMode.Always;
        return sv;
    }

    private ColorRect CreateColorRect(Shader shader)
    {
        var rect = new ColorRect();
        rect.SetAnchorsPreset(LayoutPreset.FullRect);
        var mat = new ShaderMaterial();
        mat.Shader = shader;
        rect.Material = mat;
        return rect;
    }

    public override void _Process(double delta)
    {
        var viewportSize = GetViewportRect().Size;

        // Update resolution uniform on Buffer A
        var matA = (ShaderMaterial)_rectA.Material;
        matA.SetShaderParameter("resolution", viewportSize);

        // Temporal AA: capture previous frame from SubViewport A
        var svTexture = _svA.GetTexture();
        if (svTexture != null)
        {
            var img = svTexture.GetImage();
            if (img != null)
            {
                _prevFrameTexture = ImageTexture.CreateFromImage(img);
                matA.SetShaderParameter("prev_frame", _prevFrameTexture);
            }
        }

        // Handle viewport resize
        int w = (int)viewportSize.X;
        int h = (int)viewportSize.Y;
        if (_svA.Size.X != w || _svA.Size.Y != h)
        {
            var newSize = new Vector2I(w, h);
            _svA.Size = newSize;
            _svB.Size = newSize;
            _svC.Size = newSize;
            _svD.Size = newSize;
            WireTextures(viewportSize);
        }
    }

    public override void _Input(InputEvent @event)
    {
        var matA = (ShaderMaterial)_rectA.Material;

        if (@event is InputEventMouseMotion mouseMotion)
        {
            var viewportSize = GetViewportRect().Size;
            var normalized = new Vector2(
                mouseMotion.Position.X / viewportSize.X,
                1.0f - mouseMotion.Position.Y / viewportSize.Y
            );
            matA.SetShaderParameter("mouse_pos", normalized);
        }

        if (@event is InputEventMouseButton mouseButton)
        {
            matA.SetShaderParameter("mouse_pressed", mouseButton.Pressed);
        }
    }
}
