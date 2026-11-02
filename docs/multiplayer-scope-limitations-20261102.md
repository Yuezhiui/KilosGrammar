# KilosGrammar: Two-Player Classroom Pilot — Scope and Limitations

## Purpose

KilosGrammar teaches English grammar to Grades 1–6 through movement-based play.
The new local multiplayer prototype allows exactly two registered students to
compete simultaneously in **one shared Catch the Word arena**, with two animal
characters, independent controls, scores and hearts, using **one laptop and one
webcam**. Single Player remains available.

## Interface and language

The supported on-screen instructions, teacher controls and game content are
**English only**. English-language gameplay instructions are shown in the
teacher's setup flow and in each activity's integrated tutorial. The calibration
no longer requires students to physically demonstrate left, middle and right
movements; the students simply stand in view for a measured neutral hold.

## Calibration and camera positioning

- One full-frame YOLO26n-Pose inference is shared by both player slots.
- Each registered student is enrolled into an independent tracking slot and
  measured neutral torso X coordinate during a fresh approximately 3-second
  still-standing hold, without requiring them to stand at the exact center of
  the camera frame.
- The two inset previews may crop the same camera image to keep each player
  visually centered; the game-control neutral position never drifts during
  the round when the student stops moving.
- **Distance range pending physical validation:** test 2.5, 3.0, 3.5 and
  4.0 meters from the fixed webcam, with measured floor markers. These values
  are *experimental positions*, not yet certified system operating limits.
  The installation's camera field of view, height, tilt and available room
  space determine the achievable range. Do not advertise exact real-time
  distance from an uncalibrated RGB webcam.
- A teacher should measure floor-marker spacing and validate usable player
  visibility at each candidate distance before a school deployment.

## Tracking and interruption behavior

- Each player slot may control only its own animal while pose observations
  are recent, confident and unambiguous. A hand alone, face alone or other
  unassociated person is not a new game controller.
- A child who leaves, is occluded or loses trusted tracking has their input
  disabled. Their animal stays at its last safe location and cannot collect
  words while unobserved. The other student and the shared game continue;
  background movement does not automatically open a game Pause screen.
- Seated classmates may still appear in the raw camera image and YOLO
  detection diagnostics. Only eligible assigned students display active
  gameplay skeletons and control the game. In dense crowds or full-body
  overlap, this RGB camera cannot guarantee uninterrupted tracking.
- Automatic identity tracking is an application heuristic, **not facial or
  biometric recognition**, and should not be treated as absolute proof of
  student identity when two children exchange physical positions.

## Initial multiplayer limitations

1. Exactly **two simultaneous local players**, not three or four.
2. Multiplayer applies initially to **Catch the Word**; Balloon Popping and
   Human Plane remain single-player until separately tested. A later Boat
   replacement is a future feature, not part of this prototype.
3. Requires a supported webcam, adequate lighting, full bodies visible, enough
   room and hardware capable of two-person YOLO inference.
4. No networked multiplayer; both students use one local laptop and camera.
5. A second webcam or multiple viewpoints may help a future three-/four-player
   configuration, but would require a separate study of calibration, identity
   matching and performance; two cameras do not automatically certify four
   players.
6. Classroom acceptance testing must still measure player retention, pose
   interruptions, identity mistakes, response latency, actual camera distance
   error, confusion due to spectators and learner usability.

## Results and teacher reports

The teacher can filter scoreboards by grade and section, search individual
students and export a grade-separated Excel workbook with one worksheet per
grade. The “last played” timestamp is sourced from the **latest saved
completion record per student, minigame, topic, mode and difficulty**; it is
not a full audit trail of every abandoned or repeated attempt. Existing CSV
import/export stays supported.

## Status

This document describes the **development pilot** and its proposed physical
acceptance tests. It must not be used to claim production-ready two-person
tracking or a validated 2.5–4.0 meter limit until the real camera and classroom
tests have been completed.
