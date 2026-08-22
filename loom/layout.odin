package loom

Px :: distinct f32
Pct :: distinct f32
Grow :: distinct f32

Fit :: enum u8 {
	Content,
	Stretch,
}

FIT :: Fit.Content
STRETCH :: Fit.Stretch

Size :: union {
	Px,
	Pct,
	Grow,
	Fit,
}
