# Module 00: Environment Preparation

This module contains the automated setup scripts for the workshop.

## Structure

*   **`student/`**: Scripts for participants (installs tools + monitoring agent).
*   **`instructor/`**: Scripts for the trainer (installs tools + dashboard).
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

### 👨‍🏫 For the Trainer (Instructor)

1.  Go to the `instructor` directory:
    ```bash
    cd module-00-setup/instructor
    ```
2.  Run the installation script:
    ```bash
    sudo ./setup.sh
    ```
3.  The dashboard will be accessible at `http://<YOUR-IP>:8000`.

## Validation

Once installation is complete, everything should be green. You can verify manually with:
```bash
../common/validate-env.sh
```
