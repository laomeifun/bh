using Godot;

/// <summary>
/// Black Hole shader controller.
/// Passes resolution and mouse position to the Buffer A shader uniforms.
/// </summary>
public partial class BlackHole : Control
{
    private ColorRect _bufferA;

    public override void _Ready()
    {
        _bufferA = GetNode<ColorRect>("BufferA");
        UpdateResolution();
    }

    public override void _Process(double delta)
    {
        UpdateResolution();
    }

    private void UpdateResolution()
    {
        var viewportSize = GetViewportRect().Size;
        var mat = _bufferA.Material as ShaderMaterial;
        mat?.SetShaderParameter("resolution", viewportSize);
    }

    public override void _Input(InputEvent @event)
    {
        var mat = _bufferA.Material as ShaderMaterial;
        if (mat == null) return;

        if (@event is InputEventMouseMotion mouseMotion)
        {
            var viewportSize = GetViewportRect().Size;
            var normalized = new Vector2(
                mouseMotion.Position.X / viewportSize.X,
                1.0f - mouseMotion.Position.Y / viewportSize.Y // flip Y for shader
            );
            mat.SetShaderParameter("mouse_pos", normalized);
        }

        if (@event is InputEventMouseButton mouseButton)
        {
            mat.SetShaderParameter("mouse_pressed", mouseButton.Pressed);
        }
    }
}
