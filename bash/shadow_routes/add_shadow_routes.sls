{% set script_path = './shadow_routes/add_shadow_routes.sh' %}
{% set emails = pillar.get('emails', '') %}
{% set force = pillar.get('force', False) %}
{% set verbose = pillar.get('verbose', False) %}
{% set service = pillar.get('service', '') %}
{% set arguments = [] %}

{% do arguments.append(emails) %}
{% if force %}
  {% do arguments.append('--force') %}
{% endif %}
{% if verbose %}
  {% do arguments.append('-vv') %}
{% endif %}
{% if service %}
  {% do arguments.append('--service') %}
  {% do arguments.append(service) %}
{% endif %}


script_runner:
  cmd.script:
    - source: salt://{{ script_path }}
    - args: {{ arguments | join(' ') }}
