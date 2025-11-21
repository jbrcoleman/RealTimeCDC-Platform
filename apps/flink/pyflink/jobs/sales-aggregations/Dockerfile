FROM flink:1.18.0-scala_2.12-java11

# Install Python 3.11 and wget
RUN apt-get update && \
    apt-get install -y python3.11 python3-pip python3.11-dev wget && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    ln -sf /usr/bin/python3.11 /usr/bin/python && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /opt/flink/usrlib

# Copy shared utilities
COPY apps/flink/pyflink/shared ./shared

# Copy job files
COPY apps/flink/pyflink/jobs/sales-aggregations ./job

# Install Python dependencies (boto3 for DynamoDB/S3)
RUN pip3 install --no-cache-dir -r job/requirements.txt

# Add Kafka connector JAR (Flink 1.18 uses connector version 3.0.2)
RUN wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/flink/flink-connector-kafka/3.0.2-1.18/flink-connector-kafka-3.0.2-1.18.jar && \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.4.0/kafka-clients-3.4.0.jar

# Set Python path
ENV PYTHONPATH=/opt/flink/usrlib:$PYTHONPATH

# Entrypoint will be set by Kubernetes manifest
