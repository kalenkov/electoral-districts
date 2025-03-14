import csv
import sys
import argparse

parser = argparse.ArgumentParser(description="Check that the data from two GeoJson files is identical.")
parser.add_argument("--source", required=True, help="Path to first source CSV file")
parser.add_argument("--source_orig", required=True, help="Path to original CSV file")
parser.add_argument("--intersection", required=True, help="Path to the intersection CSV file")
parser.add_argument("--difference1", required=True, help="Path to first difference (between new and old) CSV file")
parser.add_argument("--difference2", required=True, help="Path to second difference (between old and new) CSV file")
args = parser.parse_args()

rel_err=0.0000001
abs_err=1.0*(1.0/100000.0)*(1.0/100000.0) #roughly 1m2 at the equator

source_csv = [args.source, args.source_orig]
source_csv_intersect = [args.intersection]
source_csv_difference = [args.difference1, args.difference2]

csv_file = {}
csv_data = {}

def fail_message(message):
    print('[FAIL]', message)
    
def ok_message(message):
    print('[ OK ]', message)

def open_csv_file(filename):
    f = open(filename)
    if f.closed:
        fail_message('Can not open file ' + filename)
        sys.exit()
    else:
        ok_message('File ' + filename + ' was opened sucessfully')
    reader = csv.DictReader (f, delimiter=",")
    header=reader.fieldnames
    header_diff=['electoral_district', 'area', 'areaA', 'areaB']
    if filename in source_csv_intersect + source_csv_difference:
        if not all(item in header for item in header_diff):
            fail_message('Can not find all necessary columns in file ' + filename)
            sys.exit()
        else:
            ok_message('All necessary columns was found in file ' + filename)
    if filename in source_csv:
        if 'electoral_district' not in header:
            fail_message('Can not find column \'electoral_district\' in file ' + filename)
            sys.exit()
        else:
            ok_message('Column \'electoral_district\' was found in file ' + filename)
    data = {}
    for row in reader:
        if row['electoral_district'] in data:
            fail_message('Duplicate electoral_district record with electoral_district=' + row['electoral_district'] + ' in file ' + filename)
            sys.exit()
        data[row['electoral_district']] = {}
        for field in header:
            if field != 'electoral_district':
                data[row['electoral_district']][field] = row[field]
    return data
        
def check_difference(data):
    correct=True
    for electoral_district in data:
        area=float(data[electoral_district]['area'])
        areaA=float(data[electoral_district]['areaA'])
        areaB=float(data[electoral_district]['areaB'])
        if (area > abs_err or area/areaA > rel_err or area/areaB > rel_err):
            fail_message('Electoral district ' + electoral_district + ' is incorrect (the area of the difference is too large)')
            correct=False
    if correct:
        ok_message('Electoral districts difference are within errors bounds')
        
        
def check_interection(data):
    correct=True
    for electoral_district in data:
        area=float(data[electoral_district]['area'])
        areaA=float(data[electoral_district]['areaA'])
        areaB=float(data[electoral_district]['areaB'])
        if (abs(area - areaA) > abs_err or abs(area - areaB) > abs_err or 
            abs((area - areaA)/areaA) > rel_err or abs((area - areaB)/areaB) > rel_err):
            fail_message('Electoral district ' + electoral_district + ' is incorrect (the area of the intersection is too different)')
            correct=False
    if correct:
        ok_message('Electoral districts are close to each other within errors bounds')
    

def check_attributes(data, data_orig):
    correct=True
    if set(data.keys()) !=set(data_orig.keys()):
        fail_message('The data have different sets of electoral districts')
        correct=False
    else:
        ok_message('The data have the same set of electoral districts')
    for electoral_district in data:
        if data[electoral_district] != data_orig[electoral_district]:
            fail_message('Attributes for electoral district ' + electoral_district + ' are different')
            correct=False
    if correct:
        ok_message('Electoral districts have the same attributes')
    
            
        


for filename in source_csv + source_csv_intersect + source_csv_difference:
    csv_data[filename] = csv_file[filename] = open_csv_file(filename)
    ok_message('Read file ' + filename + ' sucessfully')
    
for filename in source_csv_difference:
    check_difference(csv_data[filename])
    
for filename in source_csv_intersect:
    check_interection(csv_data[filename])
    
check_attributes(csv_data[source_csv[0]], csv_data[source_csv[1]])

