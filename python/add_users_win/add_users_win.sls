# users/manage.sls

{% set users = salt['pillar.get']('users', []) %}
{% set absent_users = salt['pillar.get']('absent_users', []) %}

# 1. Manage Existing Users (Active OR Disabled)
{% for user_map in users %}
  {% for user, data in user_map.items() %}

user_manage_{{ user }}:
  user.present:
    - name: {{ user }}
    
    # LOGIC: Check if user is disabled
    {% if data.get('disabled', False) %}
    # --- LOCKDOWN MODE ---
    - password_lock: True            # Adds '!' to shadow file
    - shell: /usr/sbin/nologin       # Prevents shell login
    - groups: []                     # Optional: Strip groups or keep them
    - expire: 1                      # Expire account (1970-01-02)
    
    {% else %}
    # --- ACTIVE MODE ---
    - password: '{{ data.password }}'
    - password_lock: False           # Ensures account is unlocked
    - shell: /bin/bash
    - groups: {{ data.get('groups', []) }}
    
      # Handle Password Expiry Flag
      {% if data.get('password_never_expires') %}
    - password_never_expires: True
      {% endif %}
    
    {% endif %}

  {% endfor %}
{% endfor %}

# 2. Delete Users (Only if explicitly removed or banned)
{% for user in absent_users %}
user_remove_{{ user }}:
  user.absent:
    - name: {{ user }}
    - purge: True
{% endfor %}
