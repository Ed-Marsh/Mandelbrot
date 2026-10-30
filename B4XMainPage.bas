B4A=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=9.85
@EndOfDesignText@
Sub Class_Globals
	Private Root As B4XView
	Private xui As XUI

	'Views from the Designer
	Private ivMandel As ImageView
	Private lblInfo As Label
	Private btnReset As Button

	Private Const W As Int = 800
	Private Const H As Int = 600
	Private Const BaseScale As Double = 3.5 / 800 'complex-plane units per pixel at zoom 1
	Private Const MinScale As Double = 1e-14      'below this, Double precision breaks down

	Private centerX As Double = -0.5
	Private centerY As Double = 0
	Private scale As Double = BaseScale
	Private maxIter As Int = 250

	Private iters(W * H) As Int
	Private pixels(W * H) As Int
	Private palette(256) As Int

	Private threads(64) As Thread
	Private numThreads As Int
	Private finished As Int
	Private gen As Int        'bumping this cancels running workers
	Private busy As Boolean
	Private pending As Boolean
	Private startTime As Long
	
	Private jobGen As Int
	Private jCx, jCy, jScale As Double
	Private jIter As Int
End Sub

Public Sub Initialize
End Sub

Private Sub B4XPage_Created (Root1 As B4XView)
	Root = Root1
	Root.LoadLayout("MainPage")
	B4XPages.SetTitle(Me, "Mandelbrot")

	BuildPalette

	Dim rtStatic As JavaObject
	rtStatic.InitializeStatic("java.lang.Runtime")
	Dim rt As JavaObject = rtStatic.RunMethod("getRuntime", Null)
	numThreads = rt.RunMethod("availableProcessors", Null)
	numThreads = Max(1, Min(64, numThreads))

	RequestRender
End Sub

Private Sub BuildPalette
	For i = 0 To 255
		Dim t As Double = i / 255
		Dim r As Int = 255 * (0.5 + 0.5 * Cos(6.2831853 * t))
		Dim g As Int = 255 * (0.5 + 0.5 * Cos(6.2831853 * (t + 0.33)))
		Dim b As Int = 255 * (0.5 + 0.5 * Cos(6.2831853 * (t + 0.67)))
		palette(i) = xui.Color_RGB(r, g, b)
	Next
End Sub

'--- Rendering control ---------------------------------------------------

Private Sub RequestRender
	gen = gen + 1 'tells any running workers to stop early
	If busy Then
		pending = True 'restart when the old workers have all ended
	Else
		StartRender
	End If
End Sub

Private Sub StartRender
	busy = True
	pending = False
	finished = 0
	startTime = DateTime.Now
	lblInfo.Text = "Rendering..."

	'Snapshot the settings for this render so workers read stable values
	jobGen = gen
	jCx = centerX
	jCy = centerY
	jScale = scale
	jIter = maxIter

	For k = 0 To numThreads - 1
		threads(k).Initialise("t")
		threads(k).Start(Me, "Worker", Array(k))
	Next
End Sub

'Runs on a background thread. No UI access in here!
'Rows are interleaved (k, k+n, k+2n...) so each thread gets a similar workload.
Public Sub Worker(k As Int)
	Dim myGen As Int = jobGen
	Dim cx As Double = jCx
	Dim cy As Double = jCy
	Dim sc As Double = jScale
	Dim mi As Int = jIter
	Dim n As Int = numThreads

	Dim zr, zi, zr2, zi2, ci, cr As Double
	Dim i, row As Int
	For y = k To H - 1 Step n
		If myGen <> gen Then Return
		ci = cy + (y - H / 2) * sc
		row = y * W
		For x = 0 To W - 1
			cr = cx + (x - W / 2) * sc
			zr = 0
			zi = 0
			zr2 = 0
			zi2 = 0
			i = 0
			Do While i < mi And zr2 + zi2 <= 4
				zi = 2 * zr * zi + ci
				zr = zr2 - zi2 + cr
				zr2 = zr * zr
				zi2 = zi * zi
				i = i + 1
			Loop
			iters(row + x) = i
		Next
	Next
End Sub

'Runs on the GUI thread when each worker finishes.
Private Sub t_Ended (endedOK As Boolean, error As String)
	If endedOK = False Then Log("Worker error: " & error)
	finished = finished + 1
	If finished < numThreads Then Return
	busy = False
	If pending Then
		StartRender
	Else
		ShowResult
	End If
End Sub

Private Sub ShowResult
	Dim it As Int
	For i = 0 To W * H - 1
		it = iters(i)
		If it >= maxIter Then
			pixels(i) = xui.Color_Black
		Else
			pixels(i) = palette(Bit.And(it * 4, 255))
		End If
	Next

	'Push the whole int[] into a JavaFX WritableImage in one call
	Dim wi As JavaObject
	wi.InitializeNewInstance("javafx.scene.image.WritableImage", Array(W, H))
	Dim pw As JavaObject = wi.RunMethod("getPixelWriter", Null)
	Dim pf As JavaObject
	pf.InitializeStatic("javafx.scene.image.PixelFormat")
	pw.RunMethod("setPixels", Array(0, 0, W, H, pf.RunMethod("getIntArgbInstance", Null), pixels, 0, W))
	ivMandel.As(JavaObject).RunMethod("setImage", Array(wi))

	Dim zoom As Double = BaseScale / scale
	lblInfo.Text = "Zoom " & NumberFormat(zoom, 1, 1) & "x  |  iterations " & maxIter & _
		"  |  " & numThreads & " threads  |  " & (DateTime.Now - startTime) & " ms"
End Sub

'--- Input ---------------------------------------------------------------

Private Sub ivMandel_MousePressed (EventData As MouseEvent)
	Dim newScale As Double = scale
	If EventData.PrimaryButtonDown Then
		newScale = scale / 2
	Else If EventData.SecondaryButtonDown Then
		newScale = scale * 2
	Else
		Return
	End If

	If newScale < MinScale Then
		lblInfo.Text = "Maximum zoom for Double precision reached"
		Return
	End If
	If newScale > BaseScale Then newScale = BaseScale

	'Recentre on the clicked point, then apply the zoom
	centerX = centerX + (EventData.X - W / 2) * scale
	centerY = centerY + (EventData.Y - H / 2) * scale
	scale = newScale
	UpdateIterations
	RequestRender
End Sub

Private Sub btnReset_Action
	centerX = -0.5
	centerY = 0
	scale = BaseScale
	UpdateIterations
	RequestRender
End Sub

Private Sub UpdateIterations
	Dim zoom As Double = BaseScale / scale
	maxIter = Min(10000, 250 + 100 * Logarithm(zoom, 2))
End Sub