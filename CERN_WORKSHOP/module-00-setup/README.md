# Module 00: Environment Preparation

This module contains the automated setup scripts for the workshop.

## Structure

*   **`student/`**: Scripts for participants (installs tools + monitoring agent).
*   **`common/`**: Shared scripts (Docker, K8s, Cockpit).

## Instructions

### 👨‍🎓 For Participants (Students)

1.  Go to the `student` directory:
    ```bash
    cd module-00-setup/student
    ```
2.  Run the installation script (requires `sudo`):
    ```bash
    sudo ./setup.sh
    ```
3.  The script will ask for the **Instructor's IP address** to connect your monitoring agent.

## Validation

Once installation is complete, everything should be green. You can verify manually with:
```bash
../common/validate-env.sh
```
