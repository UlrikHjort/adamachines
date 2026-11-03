# Adamachines

[![Build and test](https://github.com/UlrikHjort/adamachines/actions/workflows/ci.yml/badge.svg)](https://github.com/UlrikHjort/adamachines/actions/workflows/ci.yml)

Tiny cars, motorcycles, boats, planes, karts, tanks, hovercraft, submarines, monster trucks
and moon rovers racing round the house, in Ada and GtkAda. Seen from above, they race over a
workbench, a garden, a frozen pond, the bath, a bedroom, the sky, the kitchen floor, a muddy
backyard, a pool table, a school desk, a beach, a model railway, a fish tank, a dark attic, a
birthday party, a garage, round a Christmas tree, across a moon base, over a pumpkin patch at
Halloween, through an Easter egg hunt, across a chess board, on an alien planet and through
the Arctic on snowmobiles. Pick-ups give you turbos, shields, oil and homing rockets. Things move
across the road, and you can build tracks of your own. One player races the AI, in single races,
championships or time trials against a ghost of their best lap. Two players share a keyboard
and a screen, in a race or a duel. You play it with the keyboard only.

![Racing round Workbench Run](docs/gifs/workbench.gif)

| | |
|---|---|
| ![Attic at Night](docs/gifs/attic.gif) | ![Halloween Night](docs/gifs/halloween.gif) |
| Attic at Night: only the headlights to see by | Halloween Night: broomsticks among the pumpkins |

![The title screen](docs/screenshots/title.jpg)

| | |
|---|---|
| ![Workbench Run](docs/screenshots/workbench.jpg) | ![Garden Path](docs/screenshots/garden.jpg) |
| Workbench Run: a toy track on the bench | Garden Path: dirt, grass and stones |
| ![Frozen Pond](docs/screenshots/ice.jpg) | ![A duel](docs/screenshots/duel.jpg) |
| Frozen Pond: little grip, and holes in the ice | A duel on Sandpit Rally |
| ![Plughole Panic](docs/screenshots/bath.jpg) | ![Cloud Nine](docs/screenshots/sky.jpg) |
| Plughole Panic: speedboats round the bath | Cloud Nine: biplanes above the clouds |
| ![Bedroom Flyer](docs/screenshots/bedroom.jpg) | ![Kitchen GP](docs/screenshots/kitchen.jpg) |
| Bedroom Flyer: over the toys on the rug | Kitchen GP: road racing bikes on the floor tiles |
| ![Backyard Motocross](docs/screenshots/motocross.jpg) | ![Pool Shark](docs/screenshots/pool.jpg) |
| Backyard Motocross: dirt bikes, jumps and mud | Pool Shark: go-karts on the cloth |
| ![Desk Derby](docs/screenshots/desk.jpg) | ![Beach Blast](docs/screenshots/beach.jpg) |
| Desk Derby: tanks on squared paper | Beach Blast: hovercraft over sand and tide pools |
| ![Toy Train Town](docs/screenshots/toytown.jpg) | ![A championship](docs/screenshots/championship.jpg) |
| Toy Train Town: mind the train | A round of the Car Cup |
| ![Attic at Night](docs/screenshots/attic.jpg) | ![Fish Tank](docs/screenshots/fishtank.jpg) |
| Attic at Night: only the headlights to see by | Fish Tank: submarines over the gravel |
| ![Birthday Party](docs/screenshots/party.jpg) | ![Garage Monsters](docs/screenshots/garage.jpg) |
| Birthday Party: round the cake | Garage Monsters: monster trucks on the concrete |
| ![Christmas Tree](docs/screenshots/christmas.jpg) | ![Moon Base](docs/screenshots/moon.jpg) |
| Christmas Tree: under the tree | Moon Base: low gravity, long jumps |
| ![Workbench Leap](docs/screenshots/leap.jpg) | ![Cloud Canyon](docs/screenshots/canyon.jpg) |
| Workbench Leap: jump the gaps in the bench | Cloud Canyon: a narrow way through the cloud |
| ![Halloween Night](docs/screenshots/halloween.jpg) | ![Easter Egg Hunt](docs/screenshots/easter.jpg) |
| Halloween Night: broomsticks by the light of the pumpkins | Easter Egg Hunt: egg cars on a spring lawn |
| ![Chess Board](docs/screenshots/chess.jpg) | ![Alien Planet](docs/screenshots/alien.jpg) |
| Chess Board: between the pieces | Alien Planet: flying saucers, crystals and goo |
| ![Arctic Safari](docs/screenshots/arctic.jpg) | ![The track editor](docs/screenshots/editor.jpg) |
| Arctic Safari: snowmobiles, igloos, penguins and a polar bear | The track editor |
| ![Results](docs/screenshots/results.jpg) | |
| The results | |
| The track editor | The results |

> **Built with AI.** Written by [Claude](https://www.anthropic.com/claude) Opus 5.5 in Claude
> Code from the author's prompts. The sound and the shape of the program follow the author's
> earlier game AdaFlip.

## Getting started

    make run

That needs GNAT, gprbuild, GtkAda and PulseAudio. On Debian, Ubuntu and Mint:

    sudo apt install gnat gprbuild libgtkada20-dev libgtk-3-dev libpulse-dev

On other releases the GtkAda package may have another number in its name: `apt search libgtkada`
finds it.

No OpenGL is needed: everything is drawn with cairo. For the announcer, install `espeak-ng`
too. Without it the game is just quiet about it.

## Controls

| | Player 1 | Player 2 |
|---|---|---|
| Drive | ↑ | W |
| Brake, and reverse when stopped (planes only slow down) | ↓ | S |
| Steer | ← → | A D |
| Use the pick-up | right Ctrl, right Shift or Enter | left Ctrl, left Shift, Space or Q |

When you play alone, either set of keys drives the car and every fire key works.

| | |
|---|---|
| Pause | Esc or P |
| Everything quiet for a moment, and back | M |
| Full screen | F11 |
| Frame rate | F3 |

In the menus: ↑ ↓ to choose, ← → to change, Enter to select, Esc to go back.

## Ways to play

- **1 player race**: you against up to five AI cars, 1 to 9 laps, on any track.
- **2 player race**: two players and up to four AI cars on one screen. The camera follows
  whichever player is in front. The other player is brought up beside them if they drop off
  the screen.
- **2 player duel**: head to head, eight lights between you. Leave the other car off the screen
  and you take one of their lights. Take all eight to win.
- **Championship**: a cup of races against the same AI drivers, with points for every place
  (10, 7, 5, 3, 2, 1). The *Car Cup* has six races and the *House Cup* four. The *Speed Cup* has
  six (bikes, tanks, hovercraft, monster trucks and rovers), and the *Water and Air Cup* seven.
  The *Holiday Cup* has four (Birthday Party, Halloween, Christmas and Easter), and the *Strange
  Worlds Cup* four (Chess Board, Alien Planet, Moon Base and Attic at Night). The *Snow and Ice
  Cup* has four (Frozen Pond, Hockey Rink, Arctic Safari and Christmas Tree). The *Grand Tour*
  runs all 29 tracks. The
  standings are shown after every round, and the champion is crowned at the end.
- **Time trial**: alone against the clock and the ghost of your best lap, which is kept for
  every track.

The best lap on every track is a **record**, whatever the mode. It's shown on the title screen
and in a time trial, and the announcer tells you when you set a new one.

## Pick-ups

Rows of spinning **?** boxes lie across the track. Drive through one to pick something up, and
fire it with your fire key. The further back you are, the likelier you get a rocket or a turbo.
The leaders more often get oil and shields.

- **Turbo**: a burst of speed.
- **Shield**: six seconds in which rockets and oil can't touch you.
- **Oil**: a slick dropped behind you. Whoever drives into it loses their grip and slides. In
  the bath and the fish tank it's **soap**, and on the alien planet green **slime**.
- **Rocket**: homes on the nearest car in front of you and spins it round.

The AI uses them too. Pick-ups can be turned off in the menu.

## The tracks

Each setting has its own vehicle, its own clutter and something that moves across the road.

| Track | Vehicle | What moves across |
|---|---|---|
| *Workbench Run*: a toy track among screws, pencils, batteries and mugs. Leave the table and you fall to the floor. | sports cars | a glass marble |
| *Garden Path*: a dirt path through grass, with a jump over a stream | buggies | hopping frogs |
| *Frozen Pond*: swept ice, snow banks and holes in the ice | rally cars | a hockey puck |
| *Sandpit Rally*: a twisty garden track with deep sand | buggies | hopping frogs |
| *Bubble Bath*: a lane of floats through ducks, soap and sponges. Mind the plughole. | speedboats | a drifting rubber duck |
| *Plughole Panic*: a tighter bath course, with plugholes on the bends | speedboats | a drifting rubber duck |
| *Bedroom Flyer*: a ribbon in the air over the toys on the rug | biplanes | a paper plane |
| *Cloud Nine*: high above the clouds, with balloons and gusts | biplanes | birds |
| *Kitchen GP*: a circuit on the floor tiles, among cutlery and spilt milk | road racing bikes | a tennis ball |
| *Backyard Motocross*: dirt, jumps, whoops, mud and tyre stacks | dirt bikes | chickens |
| *Pool Shark*: a chalk-lined course on the cloth, with pockets to fall into | go-karts | pool balls |
| *Desk Derby*: a road of squared paper among erasers, coins and ink | tanks | a wind-up robot |
| *Beach Blast*: wet sand and tide pools between sandcastles | hovercraft | crabs |
| *Toy Train Town*: a model road through a model village | rally cars | the toy train, at a level crossing |
| *Workbench Leap*: two gaps in the bench to jump | sports cars | a glass marble |
| *Hockey Rink*: a tight oval on the ice | rally cars | three hockey pucks |
| *Duck Slalom*: weave between rubber ducks on the lane | speedboats | a drifting rubber duck |
| *Cloud Canyon*: a narrow way through thick cloud | biplanes | birds |
| *Fish Tank*: a sand channel through the gravel, bubbles from the air stones | submarines | goldfish |
| *Attic at Night*: dark but for your headlights and the moonlight | rally cars | a mouse |
| *Birthday Party*: round the cake, through juice and jelly | sports cars | a bouncy ball |
| *Garage Monsters*: oil stains, toolboxes and spanners on the concrete | monster trucks | a remote control car |
| *Christmas Tree*: a rug runner round the tree, its train going round | buggies | a rolling bauble |
| *Moon Base*: across the dust between craters and domes | moon rovers | an astronaut |
| *Halloween Night*: over the pumpkin patch at night, lit by jack-o'-lanterns, through fog banks. Ghosts float over the course: pass one too close and it scares you off your line with a moan. | broomsticks | bats and ghosts |
| *Easter Egg Hunt*: a pastel path past painted eggs, chocolate bunnies and straw nests | egg cars | a hopping bunny |
| *Chess Board*: a strip of baize across the board, between pawns, rooks, bishops, queens and kings | sports cars | a leaping knight |
| *Alien Planet*: purple ground, glowing crystals, tentacle plants, egg pods and pools of goo | flying saucers | slime blobs |
| *Arctic Safari*: a packed snow trail past igloos, ice blocks and seals, over frozen lakes, with holes cut for ice fishing | snowmobiles | penguins and a polar bear |

Each vehicle handles in its own way:

- **Boats** slide wide and leave a wake.
- **Planes** never stop: the brake only slows them, and off the course the air is rough.
- **Bikes** lean into turns and leave a single skid mark. Sports bikes are quick and sure on
  tarmac but lost off it. Dirt bikes hop the jumps and throw up the earth behind them.
- **Go-karts** grip hard and turn quickly.
- **Tanks** are slow, but turn on the spot and hardly notice what they drive over.
- **Hovercraft** slide on everything, and water doesn't slow them at all.
- **Submarines** are slow and smooth, and weed and currents get hold of them.
- **Monster trucks** hardly notice the floor, and bounce right over the small things (spanners,
  nuts and screws) that stop everything else.
- **Moon rovers** float: the gravity is low, so the jumps are long.
- **Broomsticks** fly like the biplanes, but make no sound but the wind.
- **Flying saucers** hover and slide like the hovercraft, their lights going round.
- **Snowmobiles** are at home in the snow, deep or packed, but their skis slide on ice.

What's under you matters: off the road you slow down, puddles, coffee, soap and milk are
slippery, and sand, foam and cloud hold you back. Boost pads push you forward, and ramps throw
you into the air. A car that falls off or into the water is put back on the road a little way
behind.

## The track editor

**TRACK EDITOR** on the title screen opens your own tracks, *My track 1* to *My track 5*. Each
one is a loop of control points:

| | |
|---|---|
| Move the point | arrow keys (with Shift: finely) |
| Next or previous point | Tab, or ] and [ |
| Add a point after this one, or delete this one | N or Insert, X or Delete |
| Wider or narrower road here | + and −, or Page Up and Page Down |
| Change the setting (and so the vehicle) | T |
| Start from a copy of a built-in track (again for the next one) | C |
| Start again from a plain loop | R |
| Another of your tracks | 1 to 5 |
| Drive it | Enter |
| Keep it and go back | Esc |

The road turns red if it runs into itself. Point 1 (in green) is the start line, and the cars
go round towards point 2. The built-in tracks are never changed: C only copies one to start
from. A track you have kept is in the track list like any other, with the clutter and the
moving hazard of its setting, and its own lap record and ghost. The slots you haven't used
yet stay out of the list. Each one is saved in `~/.adamachines/custom-1.trk` to `custom-5.trk`.
The records and ghosts are kept by the name of the track, so new tracks never mix them up.

## Options and files

The **OPTIONS** screen sets the volume of the sound and of the music, each from 0 (off) to 10,
and the announcer voice: female, male, or off. *My tracks* sets whether your own tracks come
last in the list of tracks (as they do at first) or first. The announcer speaks as loud as the sound
is set. The music is synthesised as you play, like everything else you hear.

Your choices are kept in `~/.adamachinesrc`. The lap records, the ghosts and your own tracks are
kept in `~/.adamachines/`.

## How it works

- **The track** (`tracks.adb`) is a closed spline through a few control points, sampled every
  8 units, each sample with a width. Ramps, pads, puddles and holes are placed along it, the
  clutter is scattered round it where it leaves the road clear, and the moving hazards cross it
  on straights. All of it is drawn once with cairo into a map of materials, and a vehicle asks
  that map what it is standing on.
- **The vehicles** (`cars.adb`) are bodies in the plane. Their grip only takes out sideways
  sliding as far as the surface and the kind of vehicle allow, so they drift on ice and grip
  on tarmac. Physics steps at 120 Hz, and the picture is drawn between the steps.
- **The race** (`race.adb`) holds the AI, laps, places, pick-ups, rockets and oil, the moving
  hazards, the shared camera and the duel. The AI picks a lane round hazards, moving things and
  other cars, brakes in time for the bends ahead, and uses its pick-ups when it's worth it. It
  reports what happens as events, and the sound, the particles and the HUD read them.
- **The picture**: `art.adb` paints the world once from noise textures and cairo shapes, and
  the skid marks are drawn onto that picture as the race goes on. `scene.adb` draws the part the
  camera sees each frame: the vehicles, their shadows, the moving hazards, pick-ups, rockets,
  smoke, dust, spray, sparks and the ghost. `hud.adb` draws the panels and the menus, and
  `editor.adb` the editor.
- **The sound** (`audio.adb`) is all synthesised and played through PulseAudio: an engine for
  each kind of vehicle, the effects and a small looping tune. `speech.adb` has espeak-ng say a
  few words, and `records.adb` keeps the records and ghosts.

## Tests

    make test

`simtest` has the AI race three laps on every track with pick-ups on, and checks that every car
finishes and that pick-ups are taken. A driver that steers like a keyboard (full lock or nothing)
drives two laps of every track, and two AI drivers fight a duel to the end.

`bin/shot TRACK SECONDS FILE.png [WIDTH HEIGHT [whole]]` draws a picture of a race without a
window, or with `whole` the whole world. With `SHOT_FRAMES=N` it instead writes N frames, thirty a
second and with the HUD, named FILE0001.png and on; the GIFs above were made from those with ffmpeg. The game reads `ADAMACHINES_AUTOSTART`,
`ADAMACHINES_AUTOPILOT`, `ADAMACHINES_TRACK`, `ADAMACHINES_MODE` (`RACE_1P`, `RACE_2P`,
`DUEL_2P`, `CHAMP`, `TRIAL_1P`), `ADAMACHINES_EDITOR`, `ADAMACHINES_SHOT` (a .png file) with
`ADAMACHINES_SHOT_FRAME`, and `ADAMACHINES_FULLSCREEN`. The pictures above were made with them.

## Licence

MIT, see [LICENSE](LICENSE). Adamachines isn't affiliated with any other game or toy brand.
