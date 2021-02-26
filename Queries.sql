 ----------Create table game ---------------
 CREATE TABLE game (
    id serial PRIMARY KEY,
    game_name VARCHAR(40) NOT NULL,
    start_at TIME NOT NULL,
    end_at TIME NOT NULL,
	booth_id INT,
    constraint fk_booth_id foreign key (booth_id)
		references "Booth"(booth_id) Match Simple
		on update cascade on delete cascade
);

-------------Insert attribute -------------------
INSERT INTO  game(game_name, start_at, end_at,booth_id)
VALUES ('Pick a Duck', '08:00:00', '12:00:00', 1),
        ('Water Coin Drop', '13:00:00', '17:00:00',3),
        ('Balloon Pop', '12:00:00', '17:00:00', 4),
        ('Spin the Wheel', '09:30:00', '14:00:00', 2);

----------Create table event--------------- 
CREATE TABLE event (
    event_id INT PRIMARY KEY,
    event_name VARCHAR(40) NOT NULL,
    host_name VARCHAR(40) NOT NULL,
    start_at TIME NOT NULL,
    end_at TIME NOT NULL,
    tent_id INT,
    constraint fk_tent_id foreign key (tent_id)
		references "Tent"(tent_id) Match Simple
		on update cascade on delete cascade
);

-------------Insert attribute-------------------
INSERT INTO  event(event_id, event_name, host_name, start_at, end_at, tent_id)
VALUES (01,'Dolitle Magic', 'Harry Potter', '08:00:00', '10:00:00', 2),
        (02,'Jerry and Comics', 'Jerry', '12:00:00', '14:00:00', 2),
        (03,'Hong Kong', 'Movie', '08:00:00', '12:00:00', 3),
        (04,'Jurassic Park', 'Movie','13:00:00', '17:00:00',3),
        (05,'Jazz n Soul', 'Kenny G','13:00:00', '17:00:00',1),
        (06,'Rock Pop', 'Avici','12:00:00', '17:00:00', 1),
        (07,'Lunch', 'Avici','12:00:00', '13:00:00', 4),
        (08,'Information Desk', 'Sarah','07:00:00', '18:00:00', 5);
 
--------------Create Index-------------------- 
CREATE INDEX booth_geom_idx ON "Booth" USING gist (geom);

CREATE INDEX game__idx ON "Game" USING btree (game_name);

CREATE INDEX event__idx ON "event" USING btree (event_name);

CREATE INDEX tent_geom_idx ON "tent" USING btree (name);

---------------Create View & Join---------------------
CREATE TABLE booth_game AS
    SELECT  game.booth_id, "Booth".name, game.game_name, game.start_at, game.end_at, "Booth".geom
    FROM "Booth"
    LEFT JOIN game ON game.booth_id = "Booth".id; 

CREATE TABLE tent_event AS
    SELECT  event.tent_id, "Tent".name, event.event_name, event.start_at, event.end_at, "Tent".geom
    FROM "Tent"
    LEFT JOIN event ON event.tent_id = "Tent".id;

---------------------Creating Index for the joined Booth and game table----
-----SInce it's not possible to index on a VIEW, I convert a view to a table----------
CREATE TABLE game_booth AS SELECT * FROM "Booth_game"
CREATE INDEX game_booth_idx On game_booth using Gist (geom);

------------------------------Dynamic queries---------------------
----------------To query the time and the tent where an event is holding-----------

CREATE OR replace FUNCTION tent_search(eventname varchar)  
returns table ( tentname varchar, 
				b_time time,
				e_time time)
language plpgsql
as $$
begin
return query
	select name, start_at, end_at
						from tent_event
						where event_name = eventname;
end;
$$;
--------------------Call function--------------------------------
Select tent_search('Hong Kong');

-----------------------To query all games and the respective booth--------

CREATE OR replace FUNCTION game_search()  
returns table ( boothname varchar,
				gamename varchar, 
				b_time time,
				e_time time)
language plpgsql
as $$
begin
return query
	select name, game_name, start_at, end_at
						from game_booth;
end;
$$;

-------------------To query the nearest gender based toilet ---------------------
CREATE OR replace FUNCTION toilet_search(genderb varchar)
returns table (toilettype varchar, toiletgeom geometry)
language plpgsql
as $$
begin 
return query
select "Toilet".gender, "Toilet".geom
from "Toilet", user_location
where "Toilet".gender = genderb
and "Toilet".geom && st_expand(user_location.geom,10)
order by st_distance("Toilet".geom, user_location.geom) asc
LIMIT 1;
end;
$$
----------------------Call the function-----------------------------------------
select toilet_search('Female');
------------------------To query to fairground rides and cost and distant--------------------
CREATE OR replace FUNCTION fr_search()
returns table (fair_r varchar, costt bigint)
language plpgsql
as $$
begin 
return query
Select "fairground_ride".type, "fairground_ride".cost
from "fairground_ride";
end;
$$
------------------------------Call funtion-----------------
select fr_search()
----------------Query select all game booth within a specified distance of the user-------------
CREATE OR REPLACE FUNCTION d_search(dist integer)
returns table ( name varchar, 
				game_name varchar,
				b_time time,
				e_time time)
language plpgsql
as $$
begin
return query
	select  g.name, g.game_name, g.start_at, g.end_at
	from "user_location" u
	left join game_booth g on st_dwithin(u.geom, g.geom, dist)
	order by u.id, st_distance(u.geom, g.geom);
end;
$$;
---------------------------Call function------------------------------------------
select d_search(10);
-----------------------------------------------------


---------------------I tried to Query the route to a specific Tent from a user location (but got stuck)-------------
-- But returned an empty Geometry since there is not connection between the footh_path and the centroid.-----
---------------------Lesson learnt: How to use PgRouting, to find the nearest node------
----------------------------I used it on 

---------------Centroid for each Tent---------------
ALTER TABLE "Tent" ADD COLUMN centroid GEOMETRY;
UPDATE "Tent" SET centroid = st_centroid(geom);
---------------------------------------------------
ALTER TABLE "foot_path" ADD COLUMN source INTEGER;  
ALTER TABLE "foot_path" ADD COLUMN target INTEGER;  
ALTER TABLE "foot_path" ADD COLUMN length FLOAT8;  
---------------------------------------------
SELECT pgr_createTopology('foot_path',0.000001,'geom','id');
------------------------------------------------------
UPDATE foot_path SET length = ST_Length(geom::geography); 
---------------------------------------
update "Tent" set longitude = ST_X(ST_Centroid(ST_Transform(geom, 4326)));
update "Tent" set latitude  = ST_Y(ST_Centroid(ST_Transform(geom, 4326)));
-----------------------------------------------
CREATE INDEX idx_tent_geom ON "Tent" USING GIST(geom);
---------------------------------------------
UPDATE "Tent" SET tent_id = f.id
FROM foot_path_vertices_pgr f
	WHERE st_dwithin("Tent".geom, f.the_geom,0.000001);
--------------------------------------------------
SELECT  
    d.seq, d.node, d.edge, d.cost, e.geom AS edge_geom
FROM  
    pgr_dijkstra(
    -- edges
        'SELECT gid AS id, source, target, length AS cost FROM foot_path', 
    -- source node 
        (SELECT tent_id FROM "Tent" WHERE name = 'Jazz and Chill'), 
    -- target node                                                                                    
        (SELECT place_id FROM places WHERE common_name = 'Benaroya Hall' AND city_feature = 'General Attractions'), 
        FALSE
    ) as d                                         
    LEFT JOIN streets AS e ON d.edge = e.gid 
ORDER BY d.seq;  
------------------------Doing the same for user location-----
ALTER TABLE "user_location" add column loc_id integer;
---------------------------lat and long col on
ALTER TABLE "user_location" ADD COLUMN longitude FLOAT8;
ALTER TABLE "user_location" ADD COLUMN latitude FLOAT8;
update "user_location" set longitude = ST_X(ST_Centroid(ST_Transform(geom, 4326)));
update "user_location" set latitude  = ST_Y(ST_Centroid(ST_Transform(geom, 4326)));
----------------------------Indexting----------------------
CREATE INDEX idx_user_geom ON "user_location" USING GIST(geom);
----------------------------------------------
UPDATE "user_location" SET loc_id = f.id
FROM foot_path_vertices_pgr f
	WHERE st_dwithin("user_location".geom, f.the_geom,0.01);
---------------------------pgr_dijkstra Routing-----------------------------------
SELECT  
    d.seq, d.node, d.edge, d.cost, e.geom AS edge_geom
FROM  
    pgr_dijkstra(
    -- edges
        'SELECT id, source, target, length AS cost FROM foot_path', 
    -- source node 
        (SELECT tent_id FROM "Tent" WHERE name = 'Info Desk'), 
    -- target node                                                                                    
        (SELECT tent_id FROM "Tent" WHERE name = 'Jazz and Chill'), 
        TRUE
    ) as d                                         
    LEFT JOIN foot_path AS e ON d.edge = e.id 
ORDER BY d.seq;
