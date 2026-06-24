package sun.security.action;

import java.security.PrivilegedAction;

public class GetPropertyAction implements PrivilegedAction<String> {
    private String key;
    private String defaultValue;

    public GetPropertyAction(String key) {
        this.key = key;
    }

    public GetPropertyAction(String key, String defaultValue) {
        this.key = key;
        this.defaultValue = defaultValue;
    }

    public String run() {
        return defaultValue != null ? System.getProperty(key, defaultValue) : System.getProperty(key);
    }
}
