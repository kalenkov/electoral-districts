import csv

source=[]

with open('source.csv') as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        source.append(row.get ("district"))

flag=True
print("Поиск ошибок в исходных данных")
with open('splits.csv') as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        district=row.get ("district")
        if source.count(district) !=1:
            print(f"Error: район {district} упоминается в исходных данных {source.count(district)} раз")
            flag=False

with open('full.csv') as csv_file:
    reader = csv.DictReader (csv_file, delimiter=",")
    for row in reader:
        district=row.get ("district")
        if source.count(district) !=1:
            print(f"Error: район {district} упоминается в исходных данных {source.count(district)} раз")
            flag=False

if flag==True:
    print("Ошибок в исходных данных не найдено")
