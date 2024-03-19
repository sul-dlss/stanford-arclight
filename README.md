# Stanford Arclight Demo

## Starting the development server
```shell
bundle
yarn
./bin/dev
```

## Starting Solr for development
The following command will start a local Solr instance at `localhost:8983`, with a pre-loaded core named `blacklight-core`.

```shell
docker compose up
```

You can load fixture data locally: 
```shell
rake seed
```

This command will loop through all the directories under `spec/fixtures/ead`, for example `spec/fixtures/ead/ars` and `spec/fixtures/ead/uarc`, and index all the .xml files present. The names of these subdirectories must correspond with a top-level key in the `repositories.yml` file. For example, `uarc` is a top-level key in `respositories.yml`, as well as the title of a subdirectory under `spec/fixtures/ead`. A mis-match will cause indexing issues.


#### Managing data
Data for the solr and redis services are persisted using docker named volumes. You can see what volumes are currently present with:

```shell
docker volume ls
````

If you want to remove a volume (e.g. to start with a fresh database or solr core), you can run:

```shell
docker volume rm stanford-arclight_solr-data   # to remove the solr data
```
