#!/usr/bin/env python

import click
from pathlib import Path
import json
import yaml
from collections import defaultdict
from typing import Literal
from pydantic import BaseModel
import subprocess
import re
import jinja2
import shutil

terraform_prefix = """locals {
  challenge_cluster = {
    ecr_repository = local.ecr_repository,
    chall_domain   = local.chall_domain,
    region         = local.region,
    event_tag      = local.tag,
    hack_subnet_id = aws_subnet.hack_subnet.id,
    cluster_id     = aws_ecs_cluster.challenge_cluster.id,
  }
}

"""


class Attachment(BaseModel):
    dst: str
    url: str | None = None
    src: str | None = None


class TcpPort(BaseModel):
    type: Literal["tcp"]
    container_port: int
    instance_port: int
    lb_port: int


class HttpPort(BaseModel):
    type: Literal["http"]
    container_port: int
    instance_port: int
    http_subdomain: str


class Resources(BaseModel):
    cpu_limit_ms: int | None
    memory_limit_mb: int | None


class Challenge(BaseModel):
    stable_id: str
    name: str
    description: str
    flag: str
    category: str
    author: str
    difficulty: str | None = None
    points: int | Literal["dynamic"] | None = None
    files: list[Attachment]
    ticket_template: str
    healthscript: str | None = None

    privileged: bool = False
    image: str | None = None
    rate_limit: int | None = None
    env: dict[str, str] = {}
    resources: Resources | None = None
    ports: list[TcpPort | HttpPort] = []


jinja_env = jinja2.Environment(
    loader=jinja2.PackageLoader("main"),
    autoescape=jinja2.select_autoescape(),
)
template = jinja_env.get_template("challenge.jinja")


def load_challenge(path: Path) -> Challenge:
    yml = yaml.load(path.open(), yaml.SafeLoader)
    try:
        chal: Challenge = Challenge.validate(yml)
    except Exception as e:
        raise ValueError(f"Failed to load challenge {path.parent.name}") from e
    if chal.image is not None and not chal.ports:
        raise ValueError("Challenge with image but not ports")

    make_dist = path.parent / "make_dist.sh"
    if make_dist.exists():
        subprocess.run(["bash", "./make_dist.sh"], cwd=make_dist.parent, check=True)

    challenges_gen_path = Path("../challenges_gen", chal.category, chal.stable_id)
    challenges_gen_path.mkdir(parents=True, exist_ok=True)
    for file in ["challenge.yaml"] + [
        file.src for file in chal.files if file.src is not None
    ]:
        shutil.copy(path.parent / file, challenges_gen_path / file)

    return chal


def remove_blank_lines(s: str) -> str:
    return "\n".join(line for line in s.splitlines() if line.strip())


def check_unique[T](dictionary: dict[T, list[str]], thing_name: str):
    for thing, challenge_names in dictionary.items():
        if len(challenge_names) > 1:
            raise ValueError(f"Duplicate {thing_name} in challenges {challenge_names}")


@click.command()
@click.option("--ports", is_flag=True)
def main(ports):
    json.dump(Challenge.model_json_schema(), Path("challenge_schema.json").open("w"))
    challenges_gen_path = Path("../challenges_gen")
    if challenges_gen_path.exists():
        shutil.rmtree(challenges_gen_path)
    challenges_gen_path.mkdir(parents=True)
    shutil.copy(
        Path("../challenges/loader.yaml"), Path("../challenges_gen/loader.yaml")
    )

    challenges = list(Path("../challenges").rglob("challenge.yaml"))

    chals = [load_challenge(p) for p in Path("../challenges").rglob("challenge.yaml")]
    chals.sort(key=lambda x: x.stable_id)

    lb_ports: dict[int, list[str]] = defaultdict(list)
    instance_ports: dict[int, list[str]] = defaultdict(list)
    http_subdomains: dict[str, list[str]] = defaultdict(list)
    for chal in chals:
        for port in chal.ports:
            instance_ports[port.instance_port].append(chal.name)
            if not (40000 <= port.instance_port <= 42000):
                raise ValueError(f"{chal.name}: instance_port not in range")
            if isinstance(port, TcpPort):
                lb_ports[port.lb_port].append(chal.name)
                if not (13370 <= port.lb_port <= 13449):
                    raise ValueError(f"{chal.name}: lb_port not in range")
            elif isinstance(port, HttpPort):
                http_subdomains[port.http_subdomain].append(chal.name)
    if ports:
        print("lb_ports:")
        for port, names in sorted(lb_ports.items()):
            print(port, names)
        print("instance_ports:")
        for port, names in sorted(instance_ports.items()):
            print(port, names)
    if not ports:
        check_unique(lb_ports, "lb_port")
        check_unique(instance_ports, "instance_port")
    check_unique(http_subdomains, "http_subdomain")

    terraform = terraform_prefix
    for chal in chals:
        if chal.image is not None:
            terraform += remove_blank_lines(template.render(chal)) + "\n\n"
    terraform = terraform[:-1]

    if not ports:
        Path("../terraform/challenges_generated.tf").write_text(terraform)


if __name__ == "__main__":
    main()
