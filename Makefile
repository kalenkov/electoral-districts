export SHAPE_REWIND_ON_WRITE := YES

.PHONY: all
all: okrugs_diss.geojson check

source.osm: overpass.txt
	wget -O source.osm --post-file=overpass.txt "http://overpass-api.de/api/interpreter"

source.shp: source.osm
	ogr2ogr -overwrite -f "ESRI Shapefile" source.shp source.osm --config OGR_SQLITE_SYNCHRONOUS OFF --config OSM_USE_CUSTOM_INDEXING NO -lco ENCODING=UTF-8 -sql "SELECT osm_id, name AS district from multipolygons where osm_id is not null"

splits.shp: splits.geojson
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" splits.shp splits.geojson
	
splits_union.shp: splits.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" splits_union.shp splits.shp -dialect SQLITE -sql "SELECT ST_Union(geometry) FROM splits"

source_join.shp: source.shp full.csv
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT source.district AS district, source.osm_id AS osm_id, full.okrug AS okrug FROM source JOIN 'full.csv'.full AS full ON source.district = full.district"  source_join.shp source.shp

full.shp: source_join.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT source_join.district AS district, source_join.okrug AS okrug FROM source_join WHERE source_join.okrug IS NOT NULL" full.shp source_join.shp

part.shp: source_join.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT source_join.district AS district FROM source_join WHERE source_join.okrug IS NULL" part.shp source_join.shp

full_in.shp: full.shp splits_union.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Intersection(A.geometry, B.geometry) AS geometry, A.district AS district, A.okrug AS okrug FROM 'full' A, 'splits_union' B WHERE ST_Intersects(A.geometry, B.geometry)" . . -nlt POLYGON -skipfailures -nln full_in

full_out.shp: full.shp splits_union.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Difference(A.geometry, B.geometry) AS geometry, A.district AS district, A.okrug AS okrug FROM 'full' A, 'splits_union' B WHERE A.geometry != B.geometry" . . -nln full_out

part_in.shp: part.shp splits.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Intersection(A.geometry, B.geometry) AS geometry, A.*, B.'in' AS okrug FROM 'part' A, 'splits' B WHERE ST_Intersects(A.geometry, B.geometry) AND A.district=B.district" . . -nlt POLYGON -skipfailures -nln part_in

part_out.shp: part.shp splits.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Difference(A.geometry, B.geometry) AS geometry, A.*, B.'out' AS okrug FROM 'part' A, 'splits' B WHERE A.geometry != B.geometry AND A.district=B.district" . . -nln part_out

okrugs.shp: full_in.shp full_out.shp part_in.shp part_out.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" okrugs.shp full_in.shp
	ogr2ogr -f "ESRI Shapefile" -update -append okrugs.shp full_out.shp -nln okrugs
	ogr2ogr -f "ESRI Shapefile" -update -append okrugs.shp part_in.shp -nln okrugs
	ogr2ogr -f "ESRI Shapefile" -update -append okrugs.shp part_out.shp -nln okrugs

okrugs_diss.shp: okrugs.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" okrugs_diss.shp okrugs.shp -dialect SQLITE -sql "SELECT ST_Union(geometry), okrug FROM okrugs GROUP BY okrug"

okrugs_diss.geojson: okrugs_diss.shp data.csv
	rm -f okrugs_diss.geojson
	ogr2ogr -overwrite -f GeoJSON -sql "SELECT okrugs_diss.okrug AS okrug, data.name AS name, data.color_id AS color_id, data.color AS color, data.voters AS voters, data.terr AS terr FROM okrugs_diss LEFT JOIN 'data.csv'.data ON okrugs_diss.okrug = data.okrug"  okrugs_diss.geojson okrugs_diss.shp

splits.csv: splits.shp
	ogr2ogr -f CSV -dialect SQLITE -sql "SELECT splits.district AS district FROM splits" splits.csv splits.shp

source.csv: source.shp
	ogr2ogr -f CSV -dialect SQLITE -sql "SELECT source.district AS district FROM source" source.csv source.shp

.PHONY: check
check: source.csv splits.csv full.csv
	python check.py

.PHONY: clean
clean:
	rm -f *.shp *.prj *.cpg *.shx *.dbf
	rm -f okrugs_diss.geojson
	rm -f source.csv
	rm -f splits.csv
	

