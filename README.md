# electoral-districts
Script for generation of the electoral districts 

The script builds a map of single-mandate electoral districts in GeoJSON format, using, where possible, information about the boundaries of municipalities and/or urban districts that are available in the OpenStreetMap database. It makes sense to use the script if the territory of each electoral district almost everywhere coincides with the boundaries of municipalities and/or urban districts.

## Required Tools

* python, make, wget, ogr2ogr

## Initial data preparation

It is necessary to prepare information about the territories of single-member districts and a request to the OpenStreetMap database to obtain the necessary data.

### Overpass-turbo request file

The boundaries of the required municipalities and/or urban districts are stored in the OpenStreetMap database in the form of relations and can be queried from the database using the [overpass-turbo](https://overpass-turbo.eu/) service. The corresponding request must be placed in the `overpass.txt` file. The data can be also prepared in any other convenient way and saved in the `source.osm` file.

### File with data on territories that are contained entirely within the electoral district

Information about municipalities and/or districts that are contained entirely within the electoral district is indicated in the file `full.csv` in the form of a table
| district      | osm_id | electoral_district |
|---------------|--------|--------------------|
| район Крюково |        | 1                  |
| район Куркино |        | 2                  |
|     ...       |  ...   | ...                |

Information about territories, which are contained entirely within the boundaries of the corresponding electoral district is specified in the *district* and/or *osm_id* columns. The *osm_id* value can be omitted, but in this case the *district* column must contain the name of the territory as it is specified in the OpenStreetMap database (name tag) and this name must be unique among all territories obtained using the `overpass.txt` request. If the file contains *osm_id* of the corresponding relation, then the value in the *district* column can be arbitrary, since in this case the matching is based on *osm_id* value. The *electoral_district* column indicates the number of the electoral district (or any other electoral district identifier) which contains the corresponding territory

### File with data on territories that are divided between several electoral districts

Information about all municipalities and/or urban districts that are divided into several parts by the boundaries of electoral districts must be placed into the splits.geojson file, which must contain one splits polygonal layer. This file must contain a polygonal layer with the attributes *district*, *osm_id*, *inside*, *outside*. Attributes
| district     | osm_id | inside | outside |
|--------------|--------|--------|---------|
| район Щукино |        |  3     |  5      |
|     ...      |  ...   | ...    | ...     |

mean that the part of the district район Щукино contained within the corresponding polygon belongs to electoral district 3, and the remaining part belongs to electoral district 5. The script was tested only for cases where the municipality and/or urban district is divided between a maximum of two electoral districts. If the municipality and/or urban district is divided among a larger number of districts, the *outside* attribute should not specified (must be NULL). In this case, the script should also work, but this has not been tested. The script process the values specified in the *district*, *osm_id* columns in the same way, as in the case of the `full.csv` file.

Если есть такая возможность, то лучше стараться так расположить полигоны, чтобы они не пересекались. Если этого добиться невозможно, то на получающихся избирательных округах могут появиться артефакты, которые однако не влияют на правильность результата.

### Файл с дополнительными данными об избирательных округах
Дополнительные сведения об избирательных округах необходимо внести в файл `data.csv`. В нем обязательна должна быть колонка *electoral_district*. Информация из остальных колонок будет добавлена в качестве атрибутов в результирующий файл с избирательными округами.

## Использование скрипта
В каталог с файлами `Makefile` и `check.py` нужно поместить файл `overpass.txt` с текстом запроса к сервису overpass-turbo, файлы с описанием границ округов `full.csv`, `splits.geojson`, а также файл с дополнительной информацией `data.csv`.

Скрипт оформлен в виде Makefile'а. Для получения итогового файла достаточно выполнить команду *make* с каталоге, где расположены файлы. В самом конце будет выполнена проверка, все ли необходимые границы были скачаны с помощью запроса из файла `overpass.txt`. Если часть границ будет отсутствовать, то в конце выведется сообщение об этом.

## Примеры
Примеры исходных данных, для построение схемы одномандатных избирательных округов по выборам депутатов Московской городской Думы содержатся в каталогах MoscowCityDuma2014 и MoscowCityDuma2024. Там же содержится результат работы скрипта (файл `electoral_districts.geojson`) 
