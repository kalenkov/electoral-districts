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

source_in.shp: source.shp splits_union.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Intersection(A.geometry, B.geometry) AS geometry, A.district AS district, A.osm_id AS osm_id FROM 'source' A, 'splits_union' B WHERE ST_Intersects(A.geometry, B.geometry)" . . -nlt POLYGON -skipfailures -nln source_in

source_out.shp: source.shp splits_union.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Difference(A.geometry, B.geometry) AS geometry, A.district AS district, A.osm_id AS osm_id FROM 'source' A, 'splits_union' B WHERE A.geometry != B.geometry" . . -nln source_out

source_union.shp: source_in.shp source_out.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" source_union.shp source_in.shp
	ogr2ogr -f "ESRI Shapefile" -update -append source_union.shp source_out.shp -nln source_union

full_join.shp: source_union.shp full.csv
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT source_union.district AS district, source_union.osm_id AS osm_id, full.okrug AS okrug FROM source_union JOIN 'full.csv'.full AS full ON source_union.district = full.district"  full_join.shp source_union.shp

full.shp: full_join.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT full_join.district AS district, full_join.okrug AS okrug FROM full_join WHERE full_join.okrug IS NOT NULL"  full.shp full_join.shp

part.shp: full_join.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" -sql "SELECT full_join.district AS district FROM full_join WHERE full_join.okrug IS NULL"  part.shp full_join.shp

part_in.shp: part.shp splits.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Intersection(A.geometry, B.geometry) AS geometry, A.*, B.'in' AS okrug FROM 'part' A, 'splits' B WHERE ST_Intersects(A.geometry, B.geometry) AND A.district=B.district" . . -nlt POLYGON -skipfailures -nln part_in

part_out.shp: part.shp splits.shp
	ogr2ogr -lco ENCODING=UTF-8 -overwrite -dialect SQLITE -sql "SELECT ST_Difference(A.geometry, B.geometry) AS geometry, A.*, B.'out' AS okrug FROM 'part' A, 'splits' B WHERE A.geometry != B.geometry AND A.district=B.district" . . -nln part_out

okrugs.shp: full.shp part_in.shp part_out.shp
	ogr2ogr -lco ENCODING=UTF-8 -f "ESRI Shapefile" okrugs.shp full.shp
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
	

