import yaml

# Path to the YAML file
yaml_file = "kubernetes/deployment.yml"

# Load YAML file
with open(yaml_file, 'r') as stream:
    try:
        yaml_data = list(yaml.safe_load_all(stream))
    except yaml.YAMLError as exc:
        print(exc)

# Extract parameters for pods and deployments
pod_parameters = {
    "TOPIC": None,
    "DELAY_MS": None,
    "FUP": None,
    "MU": None,
    "WSLA": None,
    "FDOWN": None,
    "REB_TIME": None,
    "DI": None,
}

deployment_parameters = {
    "SLEEP": None,
    "MESSAGE_COUNT": None,
    "SCALE": None,
    "SHAPE": None,
    "TIME_TO_COMMIT" : None
}

# Iterating over items in YAML data
for item in yaml_data:
    if item["kind"] == "Pod":
        metadata = item.get("metadata", {})
        pod_name = metadata.get("name", "")

        spec = item.get("spec", {})
        containers = spec.get("containers", [])

        for container in containers:
            env = container.get("env", [])
            for param in env:
                name = param.get("name", "")
                value = param.get("value", "")
                if name in pod_parameters:
                    pod_parameters[name] = value

    elif item["kind"] == "Deployment":
        spec = item.get("spec", {})
        template = spec.get("template", {})
        spec_containers = template.get("spec", {}).get("containers", [])

        for container in spec_containers:
            env = container.get("env", [])
            for param in env:
                name = param.get("name", "")
                value = param.get("value", "")
                if name in deployment_parameters:
                    deployment_parameters[name] = value

# Print or save extracted parameters
output_file = "python/output/parameters.txt"
with open(output_file, 'w') as f:
    for key, value in pod_parameters.items():
        f.write(f"{key}: {value}\n")
    for key, value in deployment_parameters.items():
        f.write(f"{key}: {value}\n")

