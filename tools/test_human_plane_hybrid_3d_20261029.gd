# Compatibility test entrypoint. The previous optional glTF and BoxMesh gate
# assertions were superseded by the user-required default native TorusMesh
# flight scene. Inherit the stronger current native geometry/render regression,
# which also checks the retained gameplay HUD, perspective camera, imported
# title art, clouds, three rings, modes and collision-guide projections.
extends "res://tools/test_human_plane_native_torus_20261029.gd"
