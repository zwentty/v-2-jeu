// =============================================================================
// death_iris.gdshader
// Iris de fermeture pour la cinématique de mort.
// Dessine un DISQUE transparent (on voit le jeu) entouré de NOIR opaque.
// - center : position ÉCRAN normalisée (0..1) du personnage, poussée chaque
//   frame par death_sequence.gd (ne PAS supposer le centre de l'écran).
// - radius : rayon du disque transparent. Grand = tout visible, <= 0 = tout noir.
//   Animé de "grand" vers "négatif" pour fermer l'iris.
// - softness : adoucit le bord du cercle (smoothstep) pour qu'il ne soit pas dur.
// L'aspect (16:9...) est corrigé via SCREEN_PIXEL_SIZE pour un cercle, pas une ellipse.
// =============================================================================
shader_type canvas_item;

uniform float radius : hint_range(-0.5, 3.0) = 2.5;
uniform vec2 center = vec2(0.5, 0.5);
uniform float softness : hint_range(0.0, 0.5) = 0.05;

void fragment() {
	// Taille du viewport en pixels, pour corriger le ratio largeur/hauteur.
	vec2 vp = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = vp.x / vp.y;

	vec2 d = UV - center;
	d.x *= aspect; // corrige l'aspect : disque circulaire, pas ovale
	float dist = length(d);

	// dist < radius  -> transparent (0)  : on voit le jeu
	// dist > radius  -> opaque (1)        : noir
	float a = smoothstep(radius - softness, radius + softness, dist);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
