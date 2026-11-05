extends SceneTree
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func reference_cut(canvas: RefCounted, uv: Vector2, radius: float, strength: float, angle: float, seed: int, erase: bool) -> void:
	var size: int = canvas.size
	var first := Vector2i(maxi(0, int(floorf((uv.x-radius)*size))),maxi(0,int(floorf((uv.y-radius)*size))))
	var last := Vector2i(mini(size,int(ceilf((uv.x+radius)*size))),mini(size,int(ceilf((uv.y+radius)*size))))
	var cosine := cos(angle)
	var sine := sin(angle)
	for y in range(first.y,last.y):
		for x in range(first.x,last.x):
			var delta: Vector2 = (Vector2(x+0.5,y+0.5)/float(size)-uv)/radius
			var q := Vector2(cosine*delta.x+sine*delta.y,-sine*delta.x+cosine*delta.y)
			var width: float = 0.12+canvas._noise(int(floorf(q.x*23.0)),7,seed)*0.065
			var influence: float = smoothstep(0.0,0.22,1.0-Vector2(q.x,q.y/width).length())
			var amount: float = clampf(influence*strength,0.0,1.0)
			if amount <= 0.0: continue
			var mask: Color = canvas.image.get_pixel(x,y)
			mask.r = mask.r*(1.0-amount) if erase else 1.0-(1.0-mask.r)*(1.0-amount)
			canvas.image.set_pixel(x,y,mask)
			mask = canvas.image.get_pixel(x,y)
			var height: float = canvas._dent_image.get_pixel(x,y).r-mask.r*0.008-mask.g*0.003-mask.b*0.001+mask.a*0.0008
			canvas.height_image.set_pixel(x,y,Color(height,0,0,1))

func run() -> void:
	for center in [Vector2(.5,.5),Vector2(.01,.03),Vector2(.99,.98),Vector2(0,.5)]:
		for angle in [0.0,0.37,PI/2.0,-2.2]:
			for seed in [0,17,991]:
				var current = Canvas.new()
				var reference = Canvas.new()
				current.cpu_only = true
				reference.cpu_only = true
				current.initialize(96)
				reference.initialize(96)
				for c in [current,reference]:
					c.stamp(center,&"wear",.3,.8,0.1,123)
					c.stamp(center,&"dent",.2,.6,0.0,5)
				current.stamp(center,&"cut",.31,.91,angle,seed)
				reference_cut(reference,center,.31,.91,wrapf(angle,-PI,PI),seed,false)
				var erase_uv: Vector2 = (center+Vector2(.012,-.015)).clamp(Vector2.ZERO,Vector2.ONE)
				current.stamp(erase_uv,&"cut",.24,.43,angle+.11,seed+1,true)
				reference_cut(reference,erase_uv,.24,.43,wrapf(angle+.11,-PI,PI),seed+1,true)
				checks += 1
				if current.image.get_data()!=reference.image.get_data() or current.height_image.get_data()!=reference.height_image.get_data():
					failures += 1
					push_error("Cut mismatch at %s angle %s seed %s" % [center,angle,seed])
	print("CUT_BRUSH_EQUIVALENCE_TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
