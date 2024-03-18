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

#### Managing data
Data for the solr and redis services are persisted using docker named volumes. You can see what volumes are currently present with:

```shell
docker volume ls
````

If you want to remove a volume (e.g. to start with a fresh database or solr core), you can run:

```shell
docker volume rm stanford-arclight_solr-data   # to remove the solr data
```
