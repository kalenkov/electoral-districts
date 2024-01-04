.PHONY: all
all: source.gpkg check

source.osm: overpass.txt
	wget -O source.osm --post-file=overpass.txt "http://overpass-api.de/api/interpreter"

source.gpkg: source.osm
	ogr2ogr -overwrite -f "GPKG" source.gpkg source.osm --config OGR_SQLITE_SYNCHRONOUS OFF --config OSM_USE_CUSTOM_INDEXING NO -sql "SELECT osm_id, name AS district from multipolygons where osm_id is not null" -nln source
	
	ogr2ogr -f "GPKG" -overwrite source.gpkg splits.geojson -nln splits
	
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom FROM splits" -nln splits_union
	
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT source.district AS district, source.osm_id AS osm_id, full.electoral_district AS electoral_district FROM source JOIN 'full.csv'.full AS full ON (source.district = full.district AND full.osm_id='') OR (source.osm_id = full.osm_id AND full.osm_id!='')" -nln source_join
	
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT district, electoral_district FROM source_join WHERE electoral_district IS NOT NULL" -nln full

	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect OGRSQL -sql "SELECT district, osm_id FROM source_join WHERE electoral_district IS NULL" -nln part
	
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.district AS district, A.electoral_district AS electoral_district FROM full A, splits_union B WHERE ST_Intersects(A.geom, B.geom)" -nlt MULTIPOLYGON -skipfailures -nln electoral_districts

	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.district AS district, A.electoral_district AS electoral_district FROM 'full' A, splits_union B WHERE A.geom != B.geom" -nlt MULTIPOLYGON -nln electoral_districts

	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Intersection(A.geom, B.geom) AS geom, A.*, B.inside AS electoral_district FROM part A, splits B WHERE ST_Intersects(A.geom, B.geom) AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -skipfailures -nln electoral_districts

	ogr2ogr -f "GPKG" -append source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Difference(A.geom, B.geom) AS geom, A.*, B.outside AS electoral_district FROM part A, splits B WHERE A.geom != B.geom AND ((A.district=B.district AND B.osm_id IS NULL) OR (A.osm_id=B.osm_id AND B.osm_id IS NOT NULL))" -nlt MULTIPOLYGON -nln electoral_districts
	
	ogr2ogr -f "GPKG" -update source.gpkg source.gpkg -dialect SQLITE -sql "SELECT ST_Union(geom) AS geom, electoral_district FROM electoral_districts GROUP BY electoral_district" -nln electoral_districts_diss -nlt MULTIPOLYGON
	
	rm -f electoral_districts.geojson
	ogr2ogr -f GeoJSON electoral_districts.geojson source.gpkg -dialect OGRSQL -sql "SELECT electoral_districts_diss.electoral_district AS electoral_district, data.* FROM electoral_districts_diss LEFT JOIN 'data.csv'.data ON electoral_districts_diss.electoral_district = data.electoral_district" -nln electoral_districts

.PHONY: check
check: source.gpkg
	ogr2ogr -f CSV splits.csv source.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM splits"
	ogr2ogr -f CSV source.csv source.gpkg -dialect SQLITE -sql "SELECT district, osm_id FROM source"
	python check.py

.PHONY: clean
clean:
	rm -f source.gpkg
	rm -f source.csv
	rm -f splits.csv
	

