package com.insurancemegacorp.hdfssink;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.parquet.hadoop.ParquetWriter;
import org.apache.parquet.hadoop.metadata.CompressionCodecName;
import org.apache.parquet.schema.MessageType;
import org.apache.parquet.schema.MessageTypeParser;
import org.apache.parquet.hadoop.example.GroupWriteSupport;
import org.apache.parquet.example.data.Group;
import org.apache.parquet.example.data.simple.SimpleGroup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import jakarta.annotation.PreDestroy;
import jakarta.annotation.PostConstruct;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;
import java.util.List;
import java.util.ArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.apache.hadoop.security.UserGroupInformation;

@Component
public class HdfsSink implements Consumer<byte[]> {
    private static final Logger log = LoggerFactory.getLogger(HdfsSink.class);
    
    private final MeterRegistry meterRegistry;
    private final Configuration hadoopConf;
    private final BlockingQueue<String> messageQueue = new LinkedBlockingQueue<>(); 
    private final AtomicBoolean shutdownRequested = new AtomicBoolean(false);
    private final AtomicLong messagesReceived = new AtomicLong(0);
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);
    private ParquetWriter<Group> currentWriter;
    private String currentFilePath;
    private long currentFileStartTime;
    private int currentFileMessageCount = 0;

    @Value("${hdfs.namenodeUri:hdfs://namenode:8020}")
    private String namenodeUri;

    @Value("${hdfs.outputPath:/insurance-megacorp/telemetry-data-v2}")
    private String outputPath;
    
    @Value("${hdfs.client.timeout:60000}")
    private int clientTimeout;
    
    @Value("${hdfs.client.retries:3}")
    private int maxRetries;
    
    @Value("${hdfs.client.retryInterval:5000}")
    private int retryInterval;
    
    @Value("${hdfs.file.maxSizeMB:256}")
    private int maxFileSizeMB;
    
    @Value("${hdfs.file.maxAgeMinutes:60}")
    private int maxFileAgeMinutes;
    
    @Value("${hdfs.file.maxMessages:10000}")
    private int maxMessagesPerFile;
    
    @Value("${hdfs.batch.size:100}")
    private int batchSize;
    
    @Value("${hdfs.batch.timeoutSeconds:30}")
    private int batchTimeoutSeconds;
    
    @Value("${hdfs.kerberos.enabled:false}")
    private boolean kerberosEnabled;
    
    @Value("${hdfs.kerberos.principal:}")
    private String kerberosPrincipal;
    
    @Value("${hdfs.kerberos.keytab:}")
    private String kerberosKeytab;
    
    @Value("${hdfs.user:hdfs}")
    private String hdfsUser;
    
    public HdfsSink(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        this.hadoopConf = new Configuration(); // Initialize empty, will be configured in @PostConstruct
    }

    @PostConstruct
    public void initializeHadoopConfiguration() {
        configureHadoop(this.hadoopConf);
    }

    private void configureHadoop(Configuration conf) {
        conf.set("fs.defaultFS", namenodeUri);
        conf.setInt("dfs.client.socket-timeout", clientTimeout);
        conf.setInt("dfs.client.read.timeout", clientTimeout);
        conf.setInt("dfs.client.write.timeout", clientTimeout);
        conf.setInt("dfs.datanode.socket.write.timeout", clientTimeout);
        conf.setInt("ipc.client.connect.timeout", clientTimeout);
        conf.setInt("ipc.client.connect.retry.interval", retryInterval);
        conf.setInt("ipc.client.connect.max.retries", maxRetries);
        conf.setBoolean("dfs.client.use.datanode.hostname", true);
        
        if (kerberosEnabled) {
            conf.set("hadoop.security.authentication", "kerberos");
            if (!kerberosPrincipal.isEmpty() && !kerberosKeytab.isEmpty()) {
                conf.set("hadoop.security.kerberos.principal", kerberosPrincipal);
                conf.set("hadoop.security.kerberos.keytab", kerberosKeytab);
            }
        } else {
            conf.set("hadoop.security.authentication", "simple");
            // Set the user to run as hdfs user
            System.setProperty("HADOOP_USER_NAME", hdfsUser);
            UserGroupInformation.setConfiguration(conf);
        }
        
        log.info("Configured HDFS client to run as user: {}", hdfsUser);
    }
    
    @EventListener(ApplicationReadyEvent.class)
    public void validateHdfsConnection() {
        try {
            FileSystem fs = FileSystem.get(URI.create(namenodeUri), hadoopConf);
            Path testPath = new Path(outputPath);
            
            if (!fs.exists(testPath)) {
                log.info("Creating HDFS output directory: {}", outputPath);
                fs.mkdirs(testPath);
            }
            
            log.info("HDFS connection validated successfully to: {}", namenodeUri);
            fs.close();
            
            startBatchProcessor();
            
        } catch (Exception e) {
            log.error("Failed to validate HDFS connection to: {}", namenodeUri, e);
            meterRegistry.counter("hdfs_connection_failures_total").increment();
            
            // Start batch processor anyway for graceful degradation
            log.warn("Starting batch processor despite HDFS connection failure - messages will be queued");
            startBatchProcessor();
        }
    }
    
    private void startBatchProcessor() {
        scheduler.scheduleAtFixedRate(this::processBatch, 0, batchTimeoutSeconds, TimeUnit.SECONDS);
        scheduler.scheduleAtFixedRate(this::checkFileRolling, 0, 1, TimeUnit.MINUTES);
    }
    
    // Implement Consumer<byte[]> interface: accept inbound messages
    @Override
    public void accept(byte[] payload) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            String jsonMessage = new String(payload, StandardCharsets.UTF_8);
            messageQueue.offer(jsonMessage);
            messagesReceived.incrementAndGet();
            meterRegistry.counter("hdfs_messages_received_total").increment();
            sample.stop(Timer.builder("hdfs_message_processing_duration")
                .description("Time taken to queue message for HDFS processing")
                .register(meterRegistry));
        } catch (Exception e) {
            log.error("Failed to queue message for HDFS processing", e);
            meterRegistry.counter("hdfs_message_queue_failures_total").increment();
            sample.stop(Timer.builder("hdfs_message_processing_duration")
                .tag("status", "error")
                .register(meterRegistry));
        }
    }
    
    private void processBatch() {
        if (shutdownRequested.get() || messageQueue.isEmpty()) {
            return;
        }
        
        List<String> batch = new ArrayList<>();
        messageQueue.drainTo(batch, batchSize);
        
        if (batch.isEmpty()) {
            return;
        }
        
        Timer.Sample sample = Timer.start(meterRegistry);
        int retryCount = 0;
        
        while (retryCount <= maxRetries) {
            try {
                ensureWriterExists();
                
                for (String message : batch) {
                    writeMessage(message);
                    currentFileMessageCount++;
                }
                
                log.debug("Processed batch of {} messages to HDFS", batch.size());
                meterRegistry.counter("hdfs_messages_written_total").increment(batch.size());
                sample.stop(Timer.builder("hdfs_batch_processing_duration")
                    .description("Time taken to write batch to HDFS")
                    .register(meterRegistry));
                return;
                
            } catch (Exception e) {
                retryCount++;
                log.warn("Failed to process batch to HDFS (attempt {}/{})", retryCount, maxRetries + 1, e);
                
                if (retryCount <= maxRetries) {
                    closeCurrentWriter();
                    try {
                        Thread.sleep(retryInterval);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                } else {
                    log.error("Failed to process batch after {} retries, requeueing messages", maxRetries, e);
                    messageQueue.addAll(batch);
                    meterRegistry.counter("hdfs_batch_failures_total").increment();
                    sample.stop(Timer.builder("hdfs_batch_processing_duration")
                        .tag("status", "error")
                        .register(meterRegistry));
                    closeCurrentWriter();
                }
            }
        }
    }
    
    private void ensureWriterExists() throws IOException {
        if (currentWriter == null) {
            createNewWriter();
        }
    }
    
    private void createNewWriter() throws IOException {
        closeCurrentWriter();
        
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        String date = LocalDate.now().toString();
        Path dir = new Path(outputPath + "/date=" + date);
        currentFilePath = dir + "/telemetry-" + timestamp + "-" + System.currentTimeMillis() + ".parquet";
        Path file = new Path(currentFilePath);
        
        String schemaString = "message telemetry { required binary raw_json (UTF8); }";
        MessageType schema = MessageTypeParser.parseMessageType(schemaString);
        
        Configuration writerConf = new Configuration(hadoopConf);
        GroupWriteSupport.setSchema(schema, writerConf);
        
        currentWriter = org.apache.parquet.hadoop.example.ExampleParquetWriter.builder(file)
                .withConf(writerConf)
                .withCompressionCodec(CompressionCodecName.SNAPPY)
                .withWriteMode(org.apache.parquet.hadoop.ParquetFileWriter.Mode.CREATE)
                .withType(schema)
                .build();
                
        currentFileStartTime = System.currentTimeMillis();
        currentFileMessageCount = 0;
        
        log.info("Created new HDFS Parquet writer: {}", currentFilePath);
        meterRegistry.counter("hdfs_files_created_total").increment();
    }
    
    private void writeMessage(String message) throws IOException {
        if (currentWriter == null) {
            throw new IllegalStateException("Writer not initialized");
        }
        
        String schemaString = "message telemetry { required binary raw_json (UTF8); }";
        MessageType schema = MessageTypeParser.parseMessageType(schemaString);
        Group group = new SimpleGroup(schema);
        group.add("raw_json", message);
        currentWriter.write(group);
    }
    
    private void checkFileRolling() {
        if (currentWriter == null) {
            return;
        }
        
        boolean shouldRoll = false;
        String reason = "";
        
        // Check file age
        long fileAgeMillis = System.currentTimeMillis() - currentFileStartTime;
        if (fileAgeMillis > TimeUnit.MINUTES.toMillis(maxFileAgeMinutes)) {
            shouldRoll = true;
            reason = "file age exceeded " + maxFileAgeMinutes + " minutes";
        }
        
        // Check message count
        if (currentFileMessageCount >= maxMessagesPerFile) {
            shouldRoll = true;
            reason = "message count exceeded " + maxMessagesPerFile;
        }
        
        if (shouldRoll) {
            log.info("Rolling HDFS file due to: {}", reason);
            closeCurrentWriter();
        }
    }
    
    private void closeCurrentWriter() {
        if (currentWriter != null) {
            try {
                currentWriter.close();
                log.info("Closed HDFS Parquet file: {} with {} messages", currentFilePath, currentFileMessageCount);
                meterRegistry.counter("hdfs_files_closed_total").increment();
                meterRegistry.counter("hdfs_bytes_written_total").increment(getFileSize(currentFilePath));
            } catch (Exception e) {
                log.error("Error closing HDFS writer for file: {}", currentFilePath, e);
                meterRegistry.counter("hdfs_file_close_failures_total").increment();
            } finally {
                currentWriter = null;
                currentFilePath = null;
            }
        }
    }
    
    private long getFileSize(String filePath) {
        try {
            FileSystem fs = FileSystem.get(URI.create(namenodeUri), hadoopConf);
            return fs.getFileStatus(new Path(filePath)).getLen();
        } catch (Exception e) {
            log.warn("Could not get file size for: {}", filePath, e);
            return 0;
        }
    }
    
    @PreDestroy
    public void shutdown() {
        log.info("Shutting down HDFS Sink...");
        shutdownRequested.set(true);
        
        // Process remaining messages
        processBatch();
        
        closeCurrentWriter();
        
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(30, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
        
        log.info("HDFS Sink shutdown complete. Processed {} total messages", messagesReceived.get());
    }
}