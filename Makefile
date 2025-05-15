mkfile_path := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

OVERPASS_SCRIPTS = $(wildcard overpass*.txt)
OSM_SOURCES = $(patsubst overpass%.txt,source%.osm, $(OVERPASS_SCRIPTS))

FIRST_OSM_SOURCE := $(firstword $(OSM_SOURCES))
REST_OSM_SOURCES := $(filter-out $(FIRST_OSM_SOURCE),$(OSM_SOURCES))

NOQGIS ?= no

define PART_AND_SPLITS_VRT
<OGRVRTDataSource>
    <OGRVRTLayer name="tmp_part_districts">
        <SrcDataSource>tmp_part_districts.gpkg</SrcDataSource>
        <SrcLayer>tmp_part_districts</SrcLayer>
    </OGRVRTLayer>
    <OGRVRTLayer name="tmp_splits">
        <SrcDataSource>tmp_splits.gpkg</SrcDataSource>
        <SrcLayer>tmp_splits</SrcLayer>
    </OGRVRTLayer>
</OGRVRTDataSource>
endef
export PART_AND_SPLITS_VRT

define DIFF_NEW_AND_ORIG_VRT
<OGRVRTDataSource>
    <OGRVRTLayer name="diff_electoral_districts">
        <SrcDataSource>diff_electoral_districts.gpkg</SrcDataSource>
        <SrcLayer>diff_electoral_districts</SrcLayer>
    </OGRVRTLayer>
    <OGRVRTLayer name="diff_electoral_districts_orig">
        <SrcDataSource>diff_electoral_districts_orig.gpkg</SrcDataSource>
        <SrcLayer>diff_electoral_districts_orig</SrcLayer>
    </OGRVRTLayer>
</OGRVRTDataSource>
endef
export DIFF_NEW_AND_ORIG_VRT

define SOURCE_AND_SPLITS_UNION_NOQGIS_VRT
<OGRVRTDataSource>
    <OGRVRTLayer name="tmp_source">
        <SrcDataSource>tmp_source.gpkg</SrcDataSource>
        <SrcLayer>tmp_source</SrcLayer>
    </OGRVRTLayer>
    <OGRVRTLayer name="tmp_noqgis_splits_union">
        <SrcDataSource>tmp_noqgis_splits_union.gpkg</SrcDataSource>
        <SrcLayer>tmp_noqgis_splits_union</SrcLayer>
    </OGRVRTLayer>
</OGRVRTDataSource>
endef
export SOURCE_AND_SPLITS_UNION_NOQGIS_VRT

.PHONY: all
all: source.gpkg check

source%.osm: overpass%.txt
	wget -O $@ --post-file=$< "http://overpass-api.de/api/interpreter"

source.osm: overpass.txt
	wget -O source.osm --post-file=overpass.txt "http://overpass-api.de/api/interpreter"


# convert OSM data into multipolygon layer "source" in a GeoPackage source.gpkg file
# all subsequent intermediate results will be stored in file source.gpkg as separate layers
tmp_source.gpkg: $(OSM_SOURCES)
	ogr2ogr -overwrite -f "GPKG" tmp_source.gpkg $(FIRST_OSM_SOURCE) --config OGR_SQLITE_SYNCHRONOUS OFF --config OSM_USE_CUSTOM_INDEXING NO -sql "SELECT osm_id, name AS district from multipolygons where osm_id is not null" -nln tmp_source
	$(foreach file, $(REST_OSM_SOURCES), \
		ogr2ogr -append -f "GPKG" tmp_source.gpkg $(file) --config OGR_SQLITE_SYNCHRONOUS OFF --config OSM_USE_CUSTOM_INDEXING NO -sql "SELECT osm_id, name AS district from multipolygons where osm_id is not null" -nln tmp_source; \
	)

# convert splits.geojson file into polygonal layer "splits" in the file source.gpkg
tmp_splits.gpkg: splits.geojson
	ogr2ogr -f "GPKG" -overwrite tmp_splits.gpkg splits.geojson -nln tmp_splits

# convert polygonal layer "splits" into lines
tmp_split_lines.gpkg: tmp_splits.gpkg
	qgis_process run native:polygonstolines --INPUT=tmp_splits.gpkg --OUTPUT=tmp_split_lines.gpkg

# split source polygons by lines
tmp_source_splitted.gpkg: tmp_source.gpkg tmp_split_lines.gpkg
	qgis_process run native:splitwithlines --INPUT=tmp_source.gpkg --LINES=tmp_split_lines.gpkg --OUTPUT=tmp_source_splitted.gpkg


# NOQGIS PART BEGIN

# dissolve all polygons in splits layer into one multipolygon and store result in "splits_union" layer
tmp_noqgis_splits_union.gpkg: tmp_splits.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_noqgis_splits_union.gpkg tmp_splits.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom FROM tmp_splits"  -nlt MULTIPOLYGON -nln tmp_noqgis_splits_union

tmp_noqgis_source_and_splits_union.vrt: tmp_source.gpkg tmp_noqgis_splits_union.gpkg
	echo "$$SOURCE_AND_SPLITS_UNION_NOQGIS_VRT" > tmp_noqgis_source_and_splits_union.vrt

tmp_noqgis_source_splitted.gpkg: tmp_noqgis_source_and_splits_union.vrt
	ogr2ogr -f "GPKG" -overwrite tmp_noqgis_source_splitted.gpkg tmp_noqgis_source_and_splits_union.vrt -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.district AS district, A.osm_id AS osm_id FROM tmp_source A, tmp_noqgis_splits_union B WHERE ST_Intersects(A.geom, B.geom)" -nlt MULTIPOLYGON -skipfailures -nln tmp_noqgis_source_splitted

	ogr2ogr -f "GPKG" -append tmp_noqgis_source_splitted.gpkg tmp_noqgis_source_and_splits_union.vrt -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.district AS district, A.osm_id AS osm_id FROM tmp_source A, tmp_noqgis_splits_union B WHERE ST_Difference(A.geom, B.geom) IS NOT NULL" -nlt MULTIPOLYGON -nln tmp_noqgis_source_splitted

# NOQGIS PART END

ifeq ($(NOQGIS), no)
# union back all polygons with the same district attribute
tmp_source_reunion.gpkg: tmp_source_splitted.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_source_reunion.gpkg tmp_source_splitted.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom, * FROM tmp_source_splitted GROUP BY osm_id" -nln tmp_source_reunion -nlt MULTIPOLYGON
else
# union back all polygons with the same district attribute
tmp_source_reunion.gpkg: tmp_noqgis_source_splitted.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_source_reunion.gpkg tmp_noqgis_source_splitted.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom, * FROM tmp_noqgis_source_splitted GROUP BY osm_id" -nln tmp_source_reunion -nlt MULTIPOLYGON
endif

# mark all disticts, that are contained entirely within the electoral district, and store result in tmp_entire_districts.gpkg file
tmp_entire_districts.gpkg: tmp_source_reunion.gpkg full.csv
	ogr2ogr -f "GPKG" -overwrite tmp_entire_districts.gpkg tmp_source_reunion.gpkg -dialect OGRSQL -sql "SELECT tmp_source_reunion.district AS district, tmp_source_reunion.osm_id AS osm_id, full.electoral_district AS electoral_district FROM tmp_source_reunion JOIN 'full.csv'.full AS full ON (tmp_source_reunion.district = full.district AND full.osm_id='') OR (tmp_source_reunion.osm_id = full.osm_id AND full.osm_id!='')" -nln tmp_entire_districts

# select all other disticts and store them in tmp_part_districts.gpkg file
tmp_part_districts.gpkg: tmp_entire_districts.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_part_districts.gpkg tmp_entire_districts.gpkg -dialect OGRSQL -sql "SELECT district, osm_id FROM tmp_entire_districts WHERE electoral_district IS NULL" -nln tmp_part_districts

tmp_part_plus_splits.vrt: tmp_part_districts.gpkg tmp_splits.gpkg
	echo "$$PART_AND_SPLITS_VRT" > tmp_part_plus_splits.vrt

# find intersection of the splitted district with appropriate polygon from the "splits" layer
tmp_parts_intersections.gpkg: tmp_part_plus_splits.vrt
	ogr2ogr -f "GPKG" -overwrite tmp_parts_intersections.gpkg tmp_part_plus_splits.vrt -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.*, B.inside AS electoral_district FROM tmp_part_districts A, tmp_splits B WHERE ST_Intersects(A.geom, B.geom) AND B.inside IS NOT NULL AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -skipfailures -nln tmp_parts_intersections

# find difference of the splitted district with appropriate polygon from the "splits" layer
tmp_parts_difference.gpkg: tmp_part_plus_splits.vrt
	ogr2ogr -f "GPKG" -overwrite tmp_parts_difference.gpkg tmp_part_plus_splits.vrt -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.*, B.outside AS electoral_district FROM tmp_part_districts A, tmp_splits B WHERE ST_Difference(A.geom, B.geom) IS NOT NULL AND B.outside IS NOT NULL AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -nln tmp_parts_difference

# combine all parts into single layer
tmp_electoral_districts.gpkg: tmp_entire_districts.gpkg tmp_parts_intersections.gpkg tmp_parts_difference.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_electoral_districts.gpkg tmp_entire_districts.gpkg -dialect OGRSQL -sql "SELECT district, electoral_district FROM tmp_entire_districts WHERE electoral_district IS NOT NULL" -nln tmp_electoral_districts
	ogr2ogr -f "GPKG" -append tmp_electoral_districts.gpkg tmp_parts_intersections.gpkg -dialect OGRSQL -sql "SELECT district, electoral_district FROM tmp_parts_intersections" -nln tmp_electoral_districts
	ogr2ogr -f "GPKG" -append tmp_electoral_districts.gpkg tmp_parts_difference.gpkg -dialect OGRSQL -sql "SELECT district, electoral_district FROM tmp_parts_difference" -nln tmp_electoral_districts

# dissolve the regions which belong to the same electoral district
tmp_electoral_districts_dissolved.gpkg: tmp_electoral_districts.gpkg
	ogr2ogr -f "GPKG" -overwrite tmp_electoral_districts_dissolved.gpkg tmp_electoral_districts.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom, electoral_district FROM tmp_electoral_districts GROUP BY electoral_district" -nln tmp_electoral_districts_dissolved -nlt MULTIPOLYGON

# export the final result to the GeoJSON file and add the supplemental attributes from data.csv file
electoral_districts.geojson: tmp_electoral_districts_dissolved.gpkg data.csv
	rm -f electoral_districts.geojson
	ogr2ogr -f GeoJSON electoral_districts.geojson tmp_electoral_districts_dissolved.gpkg -dialect OGRSQL -sql "SELECT tmp_electoral_districts_dissolved.electoral_district AS electoral_district, data.* FROM tmp_electoral_districts_dissolved LEFT JOIN 'data.csv'.data ON tmp_electoral_districts_dissolved.electoral_district = data.electoral_district" -nln electoral_districts

diff_electoral_districts.gpkg: electoral_districts.geojson
	ogr2ogr -f "GPKG" -overwrite diff_electoral_districts.gpkg electoral_districts.geojson -dialect SQLITE -sql "SELECT GEOMETRY AS geom, * FROM electoral_districts" -nlt MULTIPOLYGON -nln diff_electoral_districts

diff_electoral_districts_orig.gpkg: electoral_districts_orig.geojson
	ogr2ogr -f "GPKG" -overwrite diff_electoral_districts_orig.gpkg electoral_districts_orig.geojson -dialect SQLITE -sql "SELECT GEOMETRY AS geom, * FROM electoral_districts" -nlt MULTIPOLYGON -nln diff_electoral_districts_orig

diff_new_and_orig.vrt: diff_electoral_districts.gpkg diff_electoral_districts_orig.gpkg
	echo "$$DIFF_NEW_AND_ORIG_VRT" > diff_new_and_orig.vrt


diff_new_and_orig_geojson.vrt: electoral_districts.geojson electoral_districts_orig.geojson
	echo "$$DIFF_NEW_AND_ORIG_GEOJSON_VRT" > diff_new_and_orig_geojson.vrt

diff_intersection.gpkg: diff_new_and_orig.vrt
	ogr2ogr -f "GPKG" -overwrite diff_intersection.gpkg diff_new_and_orig.vrt -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, ST_Area(ST_Intersection(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB, A.electoral_district AS electoral_district FROM diff_electoral_districts A, diff_electoral_districts_orig B WHERE ST_Intersects(A.geom, B.geom) AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -skipfailures -nln diff_intersection

diff_difference_new_orig.gpkg: diff_new_and_orig.vrt
	ogr2ogr -f "GPKG" -overwrite diff_difference_new_orig.gpkg diff_new_and_orig.vrt -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.electoral_district AS electoral_district, ST_Area(ST_Difference(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB FROM diff_electoral_districts A, diff_electoral_districts_orig B WHERE ST_Difference(A.geom, B.geom) IS NOT NULL AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -nln diff_difference_new_orig

diff_difference_orig_new.gpkg: diff_new_and_orig.vrt
	ogr2ogr -f "GPKG" -overwrite diff_difference_orig_new.gpkg diff_new_and_orig.vrt -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.electoral_district AS electoral_district, ST_Area(ST_Difference(A.geom, B.geom)) AS area, ST_Area(A.geom) AS areaA, ST_Area(B.geom) AS areaB FROM diff_electoral_districts_orig A, diff_electoral_districts B WHERE ST_Difference(A.geom, B.geom) IS NOT NULL AND A.electoral_district=B.electoral_district" -nlt MULTIPOLYGON -nln diff_difference_orig_new

diff_electoral_districts.csv: diff_electoral_districts.gpkg
	ogr2ogr -f CSV diff_electoral_districts.csv diff_electoral_districts.gpkg -dialect SQLITE -sql "SELECT * FROM diff_electoral_districts"

diff_electoral_districts_orig.csv: diff_electoral_districts_orig.gpkg
	ogr2ogr -f CSV diff_electoral_districts_orig.csv diff_electoral_districts_orig.gpkg -dialect SQLITE -sql "SELECT * FROM diff_electoral_districts_orig"

diff_electoral_districts_intersect.csv: diff_intersection.gpkg
	ogr2ogr -f CSV diff_electoral_districts_intersect.csv diff_intersection.gpkg -dialect SQLITE -sql "SELECT * FROM diff_intersection WHERE area IS NOT NULL"

diff_electoral_districts_difference_new_orig.csv: diff_difference_new_orig.gpkg
	ogr2ogr -f CSV diff_electoral_districts_difference_new_orig.csv diff_difference_new_orig.gpkg -dialect SQLITE -sql "SELECT * FROM diff_difference_new_orig WHERE area IS NOT NULL"

diff_electoral_districts_difference_orig_new.csv: diff_difference_orig_new.gpkg
	ogr2ogr -f CSV diff_electoral_districts_difference_orig_new.csv diff_difference_orig_new.gpkg -dialect SQLITE -sql "SELECT * FROM diff_difference_orig_new WHERE area IS NOT NULL"

.PHONY: test
test: diff_electoral_districts.csv diff_electoral_districts_orig.csv diff_electoral_districts_intersect.csv diff_electoral_districts_difference_new_orig.csv diff_electoral_districts_difference_orig_new.csv
	python ${mkfile_path}/test.py --source diff_electoral_districts.csv --source_orig diff_electoral_districts_orig.csv --intersection diff_electoral_districts_intersect.csv --difference1 diff_electoral_districts_difference_new_orig.csv --difference2 diff_electoral_districts_difference_orig_new.csv

tmp_source.csv: tmp_source.gpkg
	ogr2ogr -f CSV tmp_source.csv tmp_source.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM tmp_source"

tmp_splits.csv: tmp_splits.gpkg
	ogr2ogr -f CSV tmp_splits.csv tmp_splits.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM tmp_splits"

.PHONY: check
check: tmp_source.csv tmp_splits.csv full.csv
	python ${mkfile_path}/check.py --source tmp_source.csv --splits tmp_splits.csv --full full.csv

.PHONY: clean
clean:
	rm -f tmp_*

.PHONY: clean_diff
clean_diff:
	rm -f diff_*
	

.PHONY: clean_all
clean_all: clean clean_diff
	rm -f electoral_districts.geojson

