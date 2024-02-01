#!/bin/bash
## This script automates the process of locking memory on an elastic node aka keep it from using swap
# remember to give script permissions to execute chmod +x mem_lock.sh

# Function to disable swap
disable_swap() {
    echo "Disabling swap..."

    # Comment out any active swap entries in /etc/fstab
    sed -i '/^[^#].*swap/s/^/#/' /etc/fstab
    echo "Swap entries updated in /etc/fstab."

    ## Need to figure out how long to create a timeout for based on how much swap is being used
    # Turn off all active swap with a timeout
    timeout_duration=60 # Set the duration for the timeout in seconds
    timeout $timeout_duration swapoff -a

    if [ $? -eq 124 ]; then
        echo "Timeout occurred while executing swapoff -a. Exiting script."
        exit 1
    else
        echo "All active swap spaces turned off."
    fi
    echo "swapoff -a completed."
}

# Function to update Elasticsearch memory lock settings
update_memory_lock() {
    echo "Updating Elasticsearch memory lock settings..."

    # Check if 'bootstrap.memory_lock: true' is already set and not commented out
    if grep -q '^[[:space:]]*bootstrap.memory_lock:[[:space:]]*true' /etc/elasticsearch/elasticsearch.yml; then 
        echo "Memory lock is already set to true and active."
    
    else
        # If it's commented out or set to false set to true
        if grep -q '^[[:space:]]*#?[[:space:]]*bootstrap.memory_lock:' /etc/elasticsearch/elasticsearch.yml; then
            sed -i '/[[:space:]]*#?[[:space:]]*^bootstrap.memory_lock:/c\bootstrap.memory_lock: true' /etc/elasticsearch/elasticsearch.yml
            echo "Memory lock setting updated to true."
        else
            # If the setting doesn't exist, append it
            echo "bootstrap.memory_lock: true" >> /etc/elasticsearch/elasticsearch.yml
            echo "Memory lock setting appended to the configuration."
        fi
    fi
}

# Function to update security limits
update_security_limits() {
    echo "Updating /etc/security/limits.conf..."

    # Uncomment the settings if they are commented out
    # check if these check for the presence of a space or no space after the comment
    sed -i 's/^#\(\elasticsearch soft memlock unlimited\)/\1/' /etc/security/limits.conf
    sed -i 's/^#\(\elasticsearch hard memlock unlimited\)/\1/' /etc/security/limits.conf

    if ! grep -q "elasticsearch soft memlock unlimited" /etc/security/limits.conf; then
        echo -e "\n# allow user 'elasticsearch' mlockall\nelasticsearch soft memlock unlimited\nelasticsearch hard memlock unlimited" >> /etc/security/limits.conf

    fi
    echo "limits.conf updated..."
}

update_elasticsearch_service_file() {
    echo "Updating /usr/lib/systemd/system/elasticsearch.service..."

    # Check if 'LimitMEMLOCK=infinity' is already set (active or commented out)
    if grep -q '^[[:space:]]*#?[[:space:]]*LimitMEMLOCK=infinity' /usr/lib/systemd/system/elasticsearch.service; then
        # Uncomment or update the setting
        sed -i '/^[[:space:]]*#?[[:space:]]*LimitMEMLOCK=infinity/c\LimitMEMLOCK=infinity' /usr/lib/systemd/system/elasticsearch.service
        echo "LimitMEMLOCK=infinity setting updated to active."
    
    else
        # Append the seting doesn't exist, append it under the [Service] section
        sed -i '/^\[Service]/a LimitMEMLOCK=infinity' /usr/lib/systemd/system/elasticsearch.service
        echo "LimitMEMLOCK=infinity added under [Service] section."
    fi
}

# Function to manage Elasticsearch service
manage_elasticsearch_service() {
    echo "Updating systemctl daemon due to changes to the elasticsearch service"
    systemctl daemon-reload
    echo "Checking Elasticsearch service status..."
    if systemctl is-active --quiet elasticsearch; then
        echo "Restarting Elasticsearch service..."
        systemctl restart elasticsearch
    else
        echo "Starting Elasticsearch service..."
        systemctl start elasticsearch
    fi
}

# Execute Functions
disable_swap
update_memory_lock
update_security_limits
update_elasticsearch_service_file
manage_elasticsearch_service

echo "Elasticsearch node configuration completed."
