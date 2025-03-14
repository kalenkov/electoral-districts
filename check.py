import csv
import argparse


parser = argparse.ArgumentParser(description="Check of the consistency of the source data.")
parser.add_argument("--source", required=True, help="Path to source CSV file")
parser.add_argument("--splits", required=True, help="Path to splits CSV file")
parser.add_argument("--full", required=True, help="Path to the full CSV file")
args = parser.parse_args()

source_district=[]
source_osm_id=[]

with open(args.source) as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        source_district.append(row.get ("district"))
        source_osm_id.append(row.get ("osm_id"))

flag=True
print("Search for errors in source data")
with open(args.splits) as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        district=row.get ("district")
        if district == "":
            continue
        osm_id=row.get("osm_id")
        if osm_id == '':
            if source_district.count(district) !=1:
                print(f"Error: district {district} occurs in source.osm {source_district.count(district)} times")
                flag=False
        else:
            if osm_id not in source_osm_id:
                print(f"Error: can not find in source.osm relation with osm_id={osm_id}")
                flag=False
                

with open(args.full) as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        district=row.get ("district")
        osm_id=row.get ("osm_id")
        if osm_id == '':
            if source_district.count(district) !=1:
                print(f"Error: district {district} occurs in source.osm {source_district.count(district)} times")
                flag=False
        else:
            if osm_id not in source_osm_id:
                print(f"Error: can not find in source.osm relation with osm_id={osm_id}")
                flag=False

if flag==True:
    print("No errors found")
