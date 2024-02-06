import os

from typing import Any, List, Dict, Optional, Union

from nebari.schema import Base
from _nebari.stages.base import NebariTerraformStage


class RayIngressConfig(Base):
    enabled: Optional[bool] = True
    path: Optional[str] = "/ray"


class RayAuthConfig(Base):
    enabled: Optional[bool] = True


class RayEnvConfig(Base):
    name: str
    value: str


class RayNodeConfig(Base):
    disabled: Optional[bool] = False
    gpu: Optional[bool] = False
    replicas: Optional[int] = 0
    minReplicas: Optional[int] = 0
    maxReplicas: Optional[int] = 10
    nodeSelector: Optional[Dict[str, str]] = {}
    resources: Optional[Dict[str, Any]] = {}


class RayOperatorConfig(Base):
    enabled: Optional[bool] = True
    namespaced: Optional[bool] = True


class RayConfig(Base):
    name: Optional[str] = "ray"
    namespace: Optional[str] = None
    version: Optional[str] = "2.9.1"
    pythonVersion: Optional[str] = "3.10"
    ingress: RayIngressConfig = RayIngressConfig()
    auth: RayAuthConfig = RayAuthConfig()
    extraEnv: Optional[List[RayEnvConfig]] = []
    head: Optional[RayNodeConfig] = RayNodeConfig()
    workers: Optional[Dict[str, RayNodeConfig]] = {}
    operator: Optional[RayOperatorConfig] = RayOperatorConfig()
    logLevel: Optional[str] = "info"
    insecure: Optional[bool] = False
    values: Optional[Dict[str, Any]] = {}


class InputSchema(Base):
    ray: RayConfig = RayConfig()


def to_dict(item):
    match item:
        case dict():
            data = {}
            for k, v in item.items():
                data[k] = to_dict(v)
            return data
        case list() | tuple():
            return [to_dict(x) for x in item]
        case object(__dict__=_):
            data = {}
            for k, v in item.__dict__.items():
                if not k.startswith("_"):
                    data[k] = to_dict(v)
            return data
        case _:
            return item


class RayStage(NebariTerraformStage):
    name = "ray"
    priority = 100

    input_schema = InputSchema

    def input_vars(self, stage_outputs: Dict[str, Dict[str, Any]]):
        domain = stage_outputs["stages/04-kubernetes-ingress"]["domain"]
        cluster_oidc_issuer_url = stage_outputs["stages/02-infrastructure"]["cluster_oidc_issuer_url"]["value"]

        keycloak_url = ""
        realm_id = ""
        if self.config.ray.auth.enabled:
            keycloak_url = (
                f"{stage_outputs['stages/05-kubernetes-keycloak']['keycloak_credentials']['value']['url']}/auth/"
            )
            realm_id = stage_outputs["stages/06-kubernetes-keycloak-configuration"]["realm_id"]["value"]

        chart_ns = self.config.ray.namespace
        create_ns = True
        if chart_ns == None or chart_ns == "" or chart_ns == self.config.namespace:
            chart_ns = self.config.namespace
            create_ns = False

        return {
            "name": self.config.ray.name,
            "domain": domain,
            "cloud_provider": self.config.provider,
            "realm_id": realm_id,
            "client_id": self.config.ray.name,
            "base_url": f"https://{domain}{self.config.ray.ingress.path}/",
            "external_url": keycloak_url,
            "valid_redirect_uris": [f"https://{domain}{self.config.ray.ingress.path}/oauth2/callback"],
            "create_namespace": create_ns,
            "namespace": chart_ns,
            "nebari_namespace": self.config.namespace,
            "overrides": self.config.ray.values,
            "ingress": {"enabled": self.config.ray.ingress.enabled, "path": self.config.ray.ingress.path},
            "auth_enabled": self.config.ray.auth.enabled,
            "extraEnv": [x.__dict__ for x in self.config.ray.extraEnv] if len(self.config.ray.extraEnv) > 0 else [],
            "ray_version": self.config.ray.version,
            "python_version": self.config.ray.pythonVersion,
            "head": to_dict(self.config.ray.head),
            "workers": {k: to_dict(v) for (k, v) in self.config.ray.workers.items()},
            "cluster_name": self.config.escaped_project_name,
            "cluster_oidc_issuer_url": cluster_oidc_issuer_url,
            "log_level": self.config.ray.logLevel,
            "insecure": self.config.ray.insecure,
            "operator": self.config.ray.operator.__dict__
        }
