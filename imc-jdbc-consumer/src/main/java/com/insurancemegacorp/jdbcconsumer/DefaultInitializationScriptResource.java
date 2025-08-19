package com.insurancemegacorp.jdbcconsumer;

import java.nio.charset.StandardCharsets;
import java.util.Collection;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.springframework.core.io.ByteArrayResource;

/**
 * An in-memory script crafted for dropping-creating the table we're working with. All
 * columns are created as VARCHAR(2000).
 *
 * @author Eric Bottard
 * @author Thomas Risberg
 */
public class DefaultInitializationScriptResource extends ByteArrayResource {

    private static final Log logger = LogFactory.getLog(DefaultInitializationScriptResource.class);

    public DefaultInitializationScriptResource(String tableName, Collection<String> columns) {
        super(scriptFor(tableName, columns).getBytes(StandardCharsets.UTF_8));
    }

    private static String scriptFor(String tableName, Collection<String> columns) {
        StringBuilder result = new StringBuilder("DROP TABLE IF EXISTS ");
        result.append(tableName).append(";\n\n");

        result.append("CREATE TABLE ").append(tableName).append('(');
        int i = 0;
        for (String column : columns) {
            if (i++ > 0) {
                result.append(", ");
            }
            result.append(column).append(" VARCHAR(2000)");
        }
        result.append(");\n");
        logger.debug(String.format("Generated the following initializing script for table %s:\n%s", tableName,
                result.toString()));
        return result.toString();
    }
}
