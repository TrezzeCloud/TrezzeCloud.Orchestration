#!/usr/bin/env python3
"""Static checks for the phase-4 Azure demo manifests; does not access a cluster."""
from pathlib import Path
import yaml


ROOT = Path("k8s/cloud")
MANIFESTS = (
    ROOT / "users-demo" / "sqlserver.yaml",
    ROOT / "users-demo" / "rabbitmq.yaml",
    ROOT / "users-demo" / "users-api.yaml",
    ROOT / "catalog-demo" / "mongodb.yaml",
    ROOT / "catalog-demo" / "redis.yaml",
    ROOT / "catalog-demo" / "catalog-api.yaml",
    ROOT / "edge-demo" / "apis-ingress.yaml",
)
EXPECTED_DEPLOYMENTS = {
    "sqlserver", "rabbitmq", "users-api", "mongodb", "redis", "catalog-api"
}


def main():
    objs = []
    for filename in MANIFESTS:
        if not filename.is_file():
            raise AssertionError(f"Manifesto nao encontrado: {filename}")
        for item in yaml.safe_load_all(filename.read_text(encoding="utf-8")):
            assert isinstance(item, dict), f"Objeto YAML invalido: {filename}"
            assert item.get("apiVersion") and item.get("kind"), filename
            assert item.get("metadata", {}).get("name"), filename
            objs.append(item)

    def selected(kind):
        return {o["metadata"]["name"]: o for o in objs if o["kind"] == kind}

    deployments = selected("Deployment")
    services = selected("Service")
    pvcs = selected("PersistentVolumeClaim")
    assert EXPECTED_DEPLOYMENTS == set(deployments), deployments.keys()
    assert EXPECTED_DEPLOYMENTS == set(services), services.keys()
    assert {"sqlserver-data", "mongodb-data"} == set(pvcs), pvcs.keys()

    for name in EXPECTED_DEPLOYMENTS:
        deployment = deployments[name]
        service = services[name]
        assert service["spec"]["type"] == "ClusterIP", name
        assert (service["spec"]["selector"] ==
                deployment["spec"]["template"]["metadata"]["labels"]), name

    users = deployments["users-api"]["spec"]["template"]["spec"]["containers"][0]
    catalog = deployments["catalog-api"]["spec"]["template"]["spec"]["containers"][0]
    assert users["image"] == "USERS_API_IMAGE_PLACEHOLDER"
    assert catalog["image"] == "CATALOG_API_IMAGE_PLACEHOLDER"
    assert {"users-demo-secrets"} == {
        ref["secretRef"]["name"] for ref in users["envFrom"]
    }

    def env_for(container):
        return {e["name"]: e for e in container["env"]}

    variables = env_for(catalog)
    for key in ("ConnectionStrings__CatalogDatabase", "Redis__ConnectionString",
                "MongoDb__ConnectionString", "Jwt__SecretKey"):
        assert "valueFrom" in variables[key], f"{key} hardcoded ou ausente"
    for key in ("Elasticsearch__Endpoint", "Elasticsearch__ApiKey"):
        assert variables[key]["valueFrom"]["secretKeyRef"]["optional"] is True

    sql_env = env_for(deployments["sqlserver"]["spec"]["template"]["spec"]["containers"][0])
    mongo_env = env_for(deployments["mongodb"]["spec"]["template"]["spec"]["containers"][0])
    rabbit_env = env_for(deployments["rabbitmq"]["spec"]["template"]["spec"]["containers"][0])
    assert "valueFrom" in sql_env["MSSQL_SA_PASSWORD"]
    assert "valueFrom" in mongo_env["MONGO_INITDB_ROOT_PASSWORD"]
    assert "valueFrom" in rabbit_env["RABBITMQ_DEFAULT_PASS"]

    ingress = selected("Ingress")["fcg-apis"]
    assert ingress["spec"]["ingressClassName"] == "fcg-traefik"
    paths = {
        p["path"]: p["backend"]["service"]["name"]
        for p in ingress["spec"]["rules"][0]["http"]["paths"]
    }
    assert paths == {
        "/api/users": "users-api",
        "/api/games": "catalog-api",
        "/api/store": "catalog-api",
        "/search": "catalog-api",
    }

    values = yaml.safe_load((ROOT / "edge-demo" / "traefik-values.yaml").read_text())
    assert values["service"]["spec"]["type"] == "ClusterIP"
    assert values["api"]["dashboard"] is False
    print(f"OK: {len(MANIFESTS)} arquivos, 6 deployments, 6 services, 2 PVCs e Ingress Traefik.")


if __name__ == "__main__":
    main()
