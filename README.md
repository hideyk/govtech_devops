
---

# Task 1

## Sub-task 1A

### Requirements
- Write a bash script that counts the no. of HTTP 4xx and 5xx response statuses in the apache log file. The filename would be provided as a parameter to the script
- If the cumulative no. of errors exceed 100, send an email alert reporting on the high number of error responses and relevant information
- The script is expected to be run periodically (e.g. every hour) to check if the threshold for the errors have been met for the period of time

<br>

### Testing environment
Ubuntu 20.04.2.0 LTS (Focal Fossa)

<br>

### Requirements
Before running the script, we will require the `mailutils` package to send out emails. This can be installed via the `apt` package manager (assuming we are running on Ubuntu or Debian). For RHEL and CentOS, we'll use the `dnf` package manager to install the `mailx` package. 


For Ubuntu / Debian
```bash
sudo apt update
sudo apt install -y mailutils 
```

For RHEL / CentOS
```bash
sudo dnf install -y mailx
```


<br>

### Functionality
#### Bash program - /apache_logs_error_scanner/scan_apache_errors.sh

Configurable options:
- `threshold` (DEFAULT: 100)<br>
  Determines the threshold for total no. of HTTP 4xx and 5xx errors. Exceeding this threshold will trigger an alert email to be sent out to stakeholders.

- `hours_ago` (DEFAULT: 1)<br>
  Allows the program to scan for logs that came in `hours_ago` hours ago. Useful for debugging the program.
- `emails` <br>
  Comma-delimited string of emails to be alerted upon a successful detection
- `tmp_error_log` <br>
  Path for the temporary error log used to be sent as an attachment to indicated emails

<br>

#### Email template - /apache_logs_error_scanner/apache_error_mail_template

The email is entirely configurable based on the preference of the user. To add a new variable into the email template, don't forget to define the variable in the bash script and include an additional sed pipe under definition for `content` variable (DEFAULT: LINE 51). 


<br>

### Operationalizing
In order to enable the scanning of apache logs in our target machine, you may follow the steps below to operationalize the program.

Here we are assuming the program will only be used by a non-privileged functional ID that is running the Apache service. For the rest of this documentation, we'll refer to the ID as `foobar`

1. Using rsync or a managed SFTP client like WinSCP, copy over the directory **apache_logs_error_scanner/** to the home directory of the target machine **/home/foobar**. 

```bash
rsync -avzh /apache_logs_error_scanner foobar@<MACHINE-IP>:/home/foobar
```

2. Login as `foobar` to the target machine with a remote SSH client like PuTTY 

<br>

3. While logged in as `foobar`, configure the cronjob in our crontab
```bash
crontab -e

# The user's configured crontab list will show up
# Insert the following line into the crontab
```

> 0 * * * *  /home/foobar/apache_logs_error_scanner/scan_apache_errors.sh /PATH/TO/APACHE_LOG_FILE

<br>

Note: Ensure that `foobar` user has access to the folder that contains <APACHE_LOG_FILE>

<br>


---
## Sub-task 1B
### Requirements
As time passes, the log files for your application have piled up, and the machine is running out of storage. Briefly describe how you would resolve this in a short paragraph, taking into considerations that:
1. On rare occasion, logs up to 3 months old are required for troubleshooting/investigations
2. Audit requirements dictate that logs are to be kept for at least 7 years
3. The machine is currently storing 6 months worth of logs, and would run out of storage within the week. Increasing storage is not an option within the next 12 months.

### Proposed solution
Here we'll make a few assumptions about the system from the above requirements 
> Assumption 1: The machine is a dedicated Apache web server and the Apache service is the main contributor to decreasing storage. Thus the server can continue to store 6 months worth of logs and this won't change in the long term. 

> Assumption 2: The machine is part of a wider eco-system of machines which would necessitate an infrastructure team managing the servers. Thus there is likely light-weight decentralized log shippers (Filebeat) installed on each server to ship logs to a centralized log storage (Elasticsearch). 

The following steps can be taken to approach this problem. They are designed to complement each other to ensure latest logs (up to 3 months ago) are readily accessible on hot storage, while older logs (up to 7 years ago) can be accessed on cold storage for compliance and audit requirements.  

<br>

### Step 1: Enable apache monthly log rotation
---
Instead of having all our logs stored in a single file, we can split it up to bite-sized log chunks by enabling the [rotate logs](http://httpd.apache.org/docs/2.2/programs/rotatelogs.html) feature by updating the configuration file `httpd.conf`. 

Example:
> CustomLog "|bin/rotatelogs -l /var/log/apache2/apache.%Y.%m.%d.log 86400" common


Explanation: This creates files /var/log/apache.yyyy.mm.dd.log. Logging will switch to a new file every day at local time midnight. 

<br>

### Step 2: Housecleaning script
---
Once Step 1 is completed, we can write and enable a housecleaning script which runs every midnight to check the /var/log/apache2 directory for apache.yyyy.mm.dd.log files which are **older than 3 months** and purge them. 

Given our 2nd assumption, we can keep 3 months worth of logs on the server still and this is useful for L1/L2 investigation and troubleshooting. 

<br>

### Step 3: Implement log shipping to Elasticsearch cluster (Storage for up to 2 years)

---

From our 2nd assumption, we have [Filebeat](https://www.elastic.co/guide/en/beats/filebeat/current/configuring-howto-filebeat.html) installed on the server and ready to ship our Apache logs to our centralized Elasticsearch cluster. 

We'll store logs up to 2 years old in our Elasticsearch cluster for investigation as well as trend analysis insights if required. 

First, we'll have to write a `filebeat.yml` configuration file which defines an input, processor and output

#### **Input: Log**
```
filebeat.inputs:
- type: log
  paths:
    - /var/log/apache2/apache*.log
  ignore_older: 24h
  fields_under_root: true
```

#### **Processor: Split the log up into respective fields**   

```
processors:
  - dissect:
      tokenizer: "%{client_ip} %{identity} %{userid} %{datetime} %{timezone} %{method} %{resource} %{protocol} %{status_code} %{size|int} %{field10} %{browser}"
      field: "message"
      target_prefix: "apache_logs"
```

#### **Output: Logstash / Kafka / Elasticsearch**
Depending on how we want to handle our post-processing, implement a message queue or neither, we can finally ship the logs to Logstash, Kafka or Elasticsearch respectively. 

For this example, we'll assume that pre-processing is required before storing in Elasticsearch, thus a Logstash endpoint is required:
```
output.logstash:
  hosts: ["<LOGSTASH-MACHINE-IP>:5044"]
```


Once the `filebeat.yml` configuration file is ready, override `BEAT_CONFIG_OPTS` environment variable so we can point to the new config `filebeat.yml`
```bash
vi ~/.profile

# Insert the following line into the file
export BEAT_CONFIG_OPTS="-c /PATH/TO/filebeat.yml"

# Then exit and load our new profile
source ~/.profile
```

Now we're ready to enable our filebeat service by using the `systemctl` manager.
```bash
sysmtemctl start filebeat
```

Apache logs will now be available in our Elasticsearch cluster for investigation and trend analysis if required. 


<br>

### Step 4: Store logs older than 2 years on AWS Glacier cold storage
---
Lastly, we'll require long-term storage for logs up to 7 years for compliance and audit requirements. Thus, we'll take advantage of a low-cost, secure and durable solution [Amazon S3 Glacier](https://aws.amazon.com/s3/glacier/).

By storing our logs on S3 Glacier, we are able to ensure our logs are durable and scalable with 99.999999999% scalability with a minimum of 3 physical Availability Zone resilience. 

Not only that, there is an extremely low cost for the service. For S3 Glacier, there is a flat charge of $0.004 per GB storage/month. Depending on our data retrieval requirements, we may even store our logs on AWS S3 Glacier Deep Archive which costs $0.00099 per GB storage/month. 

<br>

By implementing these steps together, we can ensure our target machine does not run out of physical storage and we're able to access logs for investigative as well as audit requirements.

<br>

---

# Task 2

