package com.insurancemegacorp.spark;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;

public class StreamingQueue {
    private final BlockingQueue<String> queue = new LinkedBlockingQueue<>(10000);

    public void offer(String value) {
        queue.offer(value);
    }

    public String poll() {
        try {
            String v = queue.poll();
            return v != null ? v : "";
        } catch (Exception e) {
            return "";
        }
    }
}


