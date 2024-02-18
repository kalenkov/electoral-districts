mkfile_path := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: all
all: source.gpkg check

source.osm: 
	# download OSM data
	wget -O source.osm --post-file=overpass.txt "http://overpass-api.de/api/interpreter"

source.gpkg: source.osm
	# convert OSM data into multipolygon layer "source" in a GeoPackage source.gpkg file
	# all subsequent intermediate results will be stored in file source.gpkg as separate layers
	ogr2ogr -overwrite -f "GPKG" source.gpkg source.osm --config OGR_SQLITE_SYNCHRONOUS OFF --config OSM_USE_CUSTOM_INDEXING NO -sql "SELECT osm_id, name AS district from multipolygons where osm_id is not null" -nln source
	
	# convert splits.geojson file into polygonal layer "splits" in the file source.gpkg
	ogr2ogr -f "GPKG" -overwrite source.gpkg splits.geojson -nln splits
	
	# dissolve all polygons in splits layer into one multipolygon and store result in "splits_union" layer
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom FROM splits" -nln splits_union
	
	# mark all disticts, that are contained entirely within the electoral district, and store resultas "source_join" layer
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT source.district AS district, source.osm_id AS osm_id, full.electoral_district AS electoral_district FROM source JOIN 'full.csv'.full AS full ON (source.district = full.district AND full.osm_id='') OR (source.osm_id = full.osm_id AND full.osm_id!='')" -nln source_join
	
	# select all disticts, that are contained entirely within the electoral district, and store them as "full" layer
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT district, electoral_district FROM source_join WHERE electoral_district IS NOT NULL" -nln full

	# select all other disticts and store them as "part" layer
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT district, osm_id FROM source_join WHERE electoral_district IS NULL" -nln part
	
	# here is one subtle step. Let's assume that two districts A and B 
	# have boundary (indicated by stars) which partially coincides and 
	# district B is splitted between two electoral districts 
	# (cut is indicated by plus sign)
	#
	#    ************************
	#    *                      *
	#    *          A           *
	#    *                      *
	#    ************************
	#    *                 +    *
	#    *          B      +    *
	#    *                 +    *
	#    ************************
	#
	# the cut adds two additional points to the boundary of district B 
	# (intersection points). Therefore due to rounding errors districts 
	# A and B have no more the same boundary after the cut. To work
	# around this problem we need also split the district A by appropriate
	# cut. Therefore in the following two commands we combine intersection 
	# and difference between polygons in "full" layer and "splits_union" 
	# multipolygon. Effectively this operation adds points at the boundaries
	# exactly the the points where we need them. Result of the operations is
	# stored in "electoral_districts" layer
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.district AS district, A.electoral_district AS electoral_district FROM full A, splits_union B WHERE ST_Intersects(A.geom, B.geom)" -nlt MULTIPOLYGON -skipfailures -nln electoral_districts

	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.district AS district, A.electoral_district AS electoral_district FROM 'full' A, splits_union B WHERE A.geom != B.geom" -nlt MULTIPOLYGON -nln electoral_districts

	# find intersection of the splitted district with appropriate polygon from the "splits" layer
	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.*, B.inside AS electoral_district FROM part A, splits B WHERE ST_Intersects(A.geom, B.geom) AND B.inside IS NOT NULL AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -skipfailures -nln electoral_districts

	# find difference of the splitted district with appropriate polygon from the "splits" layer
	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.*, B.outside AS electoral_district FROM part A, splits B WHERE A.geom != B.geom AND B.outside IS NOT NULL AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -nln electoral_districts
	
	# dissolve the regions which belong to the same electoral district
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom, electoral_district FROM electoral_districts GROUP BY electoral_district" -nln electoral_districts_diss -nlt MULTIPOLYGON

electoral_districts.geojson: source.gpkg data.csv
	# export the final result to the GeoJSON file and add the supplemental attributes from data.csv file 
	rm -f electoral_districts.geojson
	ogr2ogr -f GeoJSON electoral_districts.geojson source.gpkg -dialect OGRSQL -sql "SELECT electoral_districts_diss.electoral_district AS electoral_district, data.* FROM electoral_districts_diss LEFT JOIN 'data.csv'.data ON electoral_districts_diss.electoral_district = data.electoral_district" -nln electoral_districts

.PHONY: check
check: source.gpkg
	ogr2ogr -f CSV splits.csv source.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM splits"
	ogr2ogr -f CSV source.csv source.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM source"
	python ${mkfile_path}/check.py

.PHONY: clean
clean:
	rm -f source.gpkg
	rm -f source.csv
	rm -f splits.csv

diff.gpkg: electoral_districts.geojson electoral_districts_orig.geojson
	#-t_srs ESRI:54034 
	ogr2ogr -f "GPKG" -overwrite diff.gpkg electoral_districts.geojson -dialect SQLITE -sql "SELECT GEOMETRY AS geom, * FROM electoral_districts" -nlt MULTIPOLYGON -nln electoral_districts
	ogr2ogr -f "GPKG" -update diff.gpkg electoral_districts_orig.geojson -dialect SQLITE -sql "SELECT GEOMETRY AS geom, * FROM electoral_districts" -nlt MULTIPOLYGON -nln electoral_districts_orig
	ogr2ogr -f "GPKG" -update diff.gpkg diff.gpkg -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, ST_Area(ST_Intersection(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB, A.electoral_district AS electoral_district FROM electoral_districts A, electoral_districts_orig B WHERE ST_Intersects(A.geom, B.geom) AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -skipfailures -nln electoral_districts_intersect
	ogr2ogr -f "GPKG" -update diff.gpkg diff.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.electoral_district AS electoral_district, ST_Area(ST_Difference(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB FROM electoral_districts A, electoral_districts_orig B WHERE A.geom != B.geom AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -nln electoral_districts_diff
	ogr2ogr -f "GPKG" -update diff.gpkg diff.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.electoral_district AS electoral_district, ST_Area(ST_Difference(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB FROM electoral_districts_orig A, electoral_districts B WHERE A.geom != B.geom AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -nln electoral_districts_diff2
	ogr2ogr -f CSV electoral_districts.csv diff.gpkg -dialect SQLITE -sql "SELECT * FROM electoral_districts"
	ogr2ogr -f CSV electoral_districts_orig.csv diff.gpkg -dialect SQLITE -sql "SELECT * FROM electoral_districts_orig"
	ogr2ogr -f CSV electoral_districts_intersect.csv diff.gpkg -dialect SQLITE -sql "SELECT * FROM electoral_districts_intersect WHERE area IS NOT NULL"
	ogr2ogr -f CSV electoral_districts_diff.csv diff.gpkg -dialect SQLITE -sql "SELECT * FROM electoral_districts_diff WHERE area IS NOT NULL"
	ogr2ogr -f CSV electoral_districts_diff2.csv diff.gpkg -dialect SQLITE -sql "SELECT * FROM electoral_districts_diff2 WHERE area IS NOT NULL"

.PHONY: clean_diff
clean_diff:
	rm -f diff.gpkg
	rm -f diff2.gpkg
	rm -f electoral_districts.csv
	rm -f electoral_districts_orig.csv
	rm -f electoral_districts_intersect.csv
	rm -f electoral_districts_diff.csv
	rm -f electoral_districts_diff2.csv
	

.PHONY: test
test: diff.gpkg
	python ${mkfile_path}/test.py


.PHONY: clean_all
clean_all: clean clean_diff
	rm -f electoral_districts.geojson

