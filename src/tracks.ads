--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The tracks.  A track is a closed spline through a few control points,
--  a road of changing width along it, and things put on and beside the
--  road: ramps, boost pads, puddles, sand, holes and the clutter of the
--  place it is in.  All of it is drawn once into a map of materials that
--  the cars ask what they stand on.  One world unit is about a twentieth
--  of a car's length.

with Geom; use Geom;

package Tracks is

   type Theme_Kind is (Workbench, Garden, Ice, Bath, Bedroom, Sky, Kitchen, Mud, Pool, Desk, Beach, Toy_Town,
                       Fish_Tank, Attic, Party, Garage, Xmas, Moon, Halloween, Easter, Chess, Alien, Arctic);

   type Vehicle_Kind is (Car, Boat, Plane, Road_Bike, Dirt_Bike, Kart, Tank, Hovercraft,
                         Submarine, Monster_Truck, Rover, Snowmobile);
   subtype Bike_Kind is Vehicle_Kind range Road_Bike .. Dirt_Bike;
   function Vehicle_Of (T : Theme_Kind) return Vehicle_Kind is
     (case T is
         when Workbench | Garden | Ice => Car,
         when Bath => Boat,
         when Bedroom | Sky | Halloween => Plane,   --  at Halloween, broomsticks
         when Kitchen => Road_Bike,
         when Mud => Dirt_Bike,
         when Pool => Kart,
         when Desk => Tank,
         when Beach | Alien => Hovercraft,   --  on the alien planet, flying saucers
         when Toy_Town | Attic | Party | Xmas | Easter | Chess => Car,
         when Fish_Tank => Submarine,
         when Garage => Monster_Truck,
         when Moon => Rover,
         when Arctic => Snowmobile);

   type Material is
     (Void,     --  nothing under the wheels: the car falls
      Floor,    --  off the road: slower, and rougher
      Road,
      Solid,    --  in the way: the car bounces off
      Water,    --  slippery
      Sand,     --  sticky
      Ramp,     --  up into the air
      Boost,    --  a push forward
      Bump);    --  low enough for a monster truck to roll over; in the way of the rest

   Track_Count : constant := 34;
   First_Custom : constant := 30;    --  the tracks made in the editor: 30 .. 34
   Custom_Slots : constant := 5;
   subtype Custom_Slot is Positive range 1 .. Custom_Slots;
   subtype Track_Id is Positive range 1 .. Track_Count;

   function Name (Id : Track_Id) return String;

   --  The track of the editor: its control points and its place
   type Control_Point is record
      X, Y, W : Float := 0.0;
   end record;
   Max_Custom : constant := 40;
   type Control_List is array (1 .. Max_Custom) of Control_Point;
   --  The track in the editor
   Custom_Points : Control_List;
   Custom_Count  : Natural := 0;
   Custom_Theme  : Theme_Kind := Workbench;
   procedure Default_Custom;   --  a plain loop to start from
   procedure Copy_Track (Id : Track_Id);   --  a built-in track to start from

   --  The tracks kept, one in each slot
   type Slot_Data is record
      Points : Control_List;
      Count  : Natural := 0;
      Theme  : Theme_Kind := Workbench;
      Saved  : Boolean := False;   --  made and kept: it is in the list of tracks
   end record;
   Slots : array (Custom_Slot) of Slot_Data;

   function Is_Custom (Id : Track_Id) return Boolean is (Id >= First_Custom);
   function Slot_Of (Id : Track_Id) return Custom_Slot is (Id - First_Custom + 1);
   function Built_In_Count return Positive is (First_Custom - 1);
   function Theme_Of (Id : Track_Id) return Theme_Kind;

   procedure Load (Id : Track_Id);
   --  Builds the track: its samples, its things and its material map
   function Current return Track_Id;
   function Theme return Theme_Kind;
   function Vehicle return Vehicle_Kind;   --  what races on the track loaded

   function Width return Float;    --  of the world
   function Height return Float;

   function Material_At (P : Vec) return Material;
   function Walls return Boolean;   --  the track loaded runs through thick going everywhere off it

   --  The road, sampled every Spacing units along its middle
   Spacing : constant := 8.0;

   type Sample is record
      P     : Vec;              --  the middle of the road
      T     : Vec;              --  the way the road goes (unit length)
      Width : Float := 100.0;
      Turn  : Float := 0.0;     --  change of heading per unit of length
   end record;

   function Count return Positive;
   function Get (I : Integer) return Sample;    --  I is taken round the lap
   function Lap_Length return Float;
   function Nearest (P : Vec; Hint : Integer := -1) return Natural;
   --  The sample nearest P; with a hint, only those near the hint are looked at

   --  The things on and beside the road
   type Shape_Kind is (Circle, Box, Ellipse);
   type Shape is record
      Kind   : Shape_Kind := Circle;
      C      : Vec;
      A      : Float := 0.0;        --  its turn
      RX, RY : Float := 10.0;       --  radius, or half length and half width
   end record;

   type Item_Kind is
     (Screw, Nut, Pencil, Mug, Tape_Roll, Ruler, Battery, Coffee_Spill, Sawdust,
      Stone, Flower, Pot, Pond, Puddle, Sand_Patch, Leaf, Stream,
      Snowman, Ice_Hole, Snow_Pile, Pine_Cone, Pine_Tree,
      Rubber_Duck, Soap, Sponge, Bubbles, Plughole, Bottle, Soap_Film,
      Toy_Block, Book, Crayon, Balloon, Cloud, Hot_Air_Balloon, Gust,
      Fork, Spoon, Bottle_Cap, Salt_Shaker, Milk_Spill, Flour, Pea,
      Hay_Bale, Tyre_Stack, Mud_Patch, Plank,
      Pocket, Snooker_Ball, Chalk_Cube, Cue,
      Eraser, Sharpener, Paper_Clip, Coin, Ink_Blot, Shavings, Rubber_Band,
      Sandcastle, Bucket, Shell, Starfish, Towel, Beach_Ball, Tide_Pool,
      Model_Tree, House, Bush,
      Castle, Chest, Seaweed, Air_Stone,
      Trunk, Rocking_Horse, Carton, Web, Dust_Pile, Moonbeam,
      Cake, Present, Party_Hat, Cupcake, Juice_Spill, Jelly, Confetti,
      Toolbox, Paint_Tin, Spanner, Oil_Stain, Drain,
      Xmas_Tree, Bauble, Candy_Cane, Needles,
      Crater, Moon_Rock, Lander, Flag, Dome,
      Pumpkin, Gravestone, Cauldron, Candle, Fog,
      Easter_Egg, Choc_Bunny, Basket, Daffodil, Nest,
      Pawn, Rook, Knight_Piece, Bishop, Queen, King, Chess_Clock,
      Crystal, Alien_Plant, Goo_Pool, Egg_Pod, Spire, Spores,
      Igloo, Ice_Block, Seal, Ice_Patch, Fish_Hole,
      Ramp_Piece, Boost_Pad);

   function Below (K : Item_Kind) return Boolean is
     (K in Toy_Block | Book | Crayon | Cloud);
   --  Far below the planes: drawn under the course, and nothing to them

   type Item is record
      Kind : Item_Kind := Screw;
      S    : Shape;
      Mat  : Material := Floor;
      Tone : Float := 0.5;          --  a little variety in how it looks
   end record;

   function Is_Below (It : Item) return Boolean is (Below (It.Kind) and then It.Mat = Floor);

   function Item_Count return Natural;
   function Get_Item (I : Positive) return Item;

   --  The workbench is a table: outside its top there is only the floor far below
   function Has_Table return Boolean;
   function Table_Left return Float;
   function Table_Top return Float;
   function Table_Right return Float;
   function Table_Bottom return Float;

   procedure Grid_Slot (K : Positive; P : out Vec; Heading : out Float);
   --  The K-th place on the starting grid

   function Inside (S : Shape; P : Vec; Margin : Float := 0.0) return Boolean;

   --  Things that move across the road on a beat of their own
   type Mover_Kind is
     (Marble, Frog, Puck, Drifting_Duck, Paper_Plane, Bird, Tennis_Ball, Chicken,
      Pool_Ball, Robot, Crab, Train,
      Fish, Mouse, Bouncy_Ball, RC_Car, Rolling_Bauble, Astronaut, Bat, Bunny, Knight_Hop, Blob,
      Ghost,   --  floats over the course, and scares off whoever comes too near
      Penguin, Polar_Bear,
      Circle_Train);   --  round the Christmas tree: A its middle, B.X how far out
   type Mover is record
      Kind   : Mover_Kind := Marble;
      A, B   : Vec;             --  the ends of its way
      Period : Float := 5.0;    --  seconds for the way there and back
      Phase  : Float := 0.0;
      Radius : Float := 10.0;   --  the train: half its width
   end record;

   Train_Length : constant := 150.0;

   function Mover_Count return Natural;
   function Get_Mover (I : Positive) return Mover;
   procedure Mover_At (M : Mover; T : Float; P : out Vec; Heading : out Float;
                       Visible : out Boolean; Lift : out Float);
   --  Where it is T seconds into the race; Lift for a hop, or how high it flies

end Tracks;
