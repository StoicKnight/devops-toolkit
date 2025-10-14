{%- if grains['os'] == 'Windows' %}
{%-   set old_conf_dir = 'C:\\salt\\conf' %}
{%-   set new_conf_dir = 'C:\\ProgramData\\Salt Project\\Salt\\conf' %}
{%-   if salt['file.directory_exists'](new_conf_dir) %}
{%-     set conf_dir = new_conf_dir %}
{%-   else %}
{%-     set conf_dir = old_conf_dir %}
{%-   endif %}
{%-   set minion_conf = conf_dir ~ '\\minion' %}
{%-   set grains_conf = conf_dir ~ '\\grains' %}
{%-   set backup_dir = 'C:\\Windows\\Temp\\' %}
{%-   set installer_url = 'https://packages.broadcom.com/artifactory/saltproject-generic/windows/3007.6/Salt-Minion-3007.6-Py3-AMD64-Setup.exe' %}
{%-   set installer_path = backup_dir ~ 'Salt-Minion-3007.6-Py3-AMD64-Setup.exe' %}
{%- elif grains['os_family'] == 'Debian' %}
{%-   set minion_conf = '/etc/salt/minion' %}
{%-   set grains_conf = '/etc/salt/grains' %}
{%-   set backup_dir = '/tmp/' %}
{%- endif %}

{%- set timestamp = salt['time.strftime']('%Y%m%d_%H%M%S') %}


{%- if grains['os'] == 'Windows' %}

backup_minion_config_windows:
  file.copy:
    - name: {{ backup_dir }}minion_{{ grains['id'] }}_{{ timestamp }}.bak
    - source: {{ minion_conf }}
    - makedirs: True

backup_grains_config_windows:
    - name: {{ backup_dir }}grains_{{ grains['id'] }}_{{ timestamp }}.bak
    - source: {{ grains_conf }}
    - makedirs: True

download_minion_installer:
  file.managed:
    - name: {{ installer_path }}
    - source: {{ installer_url }}
    - source_hash: sha256=5a90654253923998451379b215897b496afcb45d84b1f1d0dca465b1e896b0e8
    - require:
      - file: backup_minion_config_windows
      - cmd: backup_grains_config_windows

upgrade_salt_minion_windows:
  cmd.run:
    - name: 'powershell.exe -Command "Start-Process -FilePath \"{{ installer_path }}\" -ArgumentList ''/move-config /S'' -Wait"'
    - unless: 'powershell.exe -Command "(Get-ItemProperty -Path ''HKLM:\\Software\\Salt Project\\Salt'').Version -eq ''3007.6''"'
    - require:
      - file: download_minion_installer

restore_minion_config_windows:
  file.copy:
    - name: {{ minion_conf }}
    - source: {{ backup_dir }}minion_{{ grains['id'] }}_{{ timestamp }}.bak
    - require:
      - cmd: upgrade_salt_minion_windows

restore_grains_config_windows:
  file.copy:
    - name: {{ grains_conf }}
    - source: {{ backup_dir }}grains_{{ grains['id'] }}_{{ timestamp }}.bak
    - require:
      - cmd: upgrade_salt_minion_windows


{%- elif grains['os_family'] == 'Debian' %}

backup_minion_config_debian:
  file.copy:
    - name: {{ backup_dir }}minion_{{ grains['id'] }}_{{ timestamp }}.bak
    - source: {{ minion_conf }}
    - makedirs: True

backup_grains_config_debian:
  file.copy:
    - name: {{ backup_dir }}grains_{{ grains['id'] }}_{{ timestamp }}.bak
    - source: {{ grains_conf }}
    - makedirs: True

upgrade_salt_minion_debian:
  pkg.installed:
    - name: salt-minion
    - version: 3007.6
    - refresh: True
    - require:
      - file: backup_minion_config_debian
      - cmd: backup_grains_config_debian

restart_salt_minion_service:
  service.running:
    - name: salt-minion
    - enable: True
    - watch:
      - pkg: upgrade_salt_minion_debian

{%- endif %}
