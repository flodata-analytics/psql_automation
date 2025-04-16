# PostgreSQL Ownership Transfer Tool (PowerShell)

## Overview

This PowerShell script provides an interactive command-line interface to:

1.  **Connect** to a PostgreSQL server.
2.  **List** databases and users on the server.
3.  **View** tables owned by a specific user, with options to filter by database and schema.
4.  **Transfer** ownership of selected tables (or all listed tables) from the specified user to another existing user.

It relies on the `psql` command-line tool being installed and accessible in your system's PATH. The script includes input validation for credentials, database/schema selections, and user choices.

## Prerequisites

1.  **PowerShell:** The script is designed to run in a PowerShell environment (typically available by default on Windows).
2.  **PostgreSQL Client Tools:** You **must** have the PostgreSQL client tools installed on the machine where you run this script. Specifically, the `psql.exe` executable is required.
3.  **`psql` in PATH:** The directory containing `psql.exe` must be included in your system's `PATH` environment variable so PowerShell can find and execute it.
4.  **Permissions:** The PostgreSQL user whose credentials you provide must have sufficient privileges to:
    * Connect to the `postgres` database (initially) and any target databases.
    * Query `pg_database`, `pg_user`, `pg_class`, and `pg_namespace` system catalogs.
    * Execute `ALTER TABLE ... OWNER TO ...` commands (often requires superuser privileges or specific grants).

## How to Use

1.  **Save the Script:** Save the provided script code to a file, for example, `postgres_owner_transfer.ps1`.
2.  **Open PowerShell:** Launch a PowerShell terminal. You might need to run it as an Administrator depending on your environment and permissions.
3.  **Navigate to Script Directory:** Use the `cd` command to change to the directory where you saved the script file.
    ```powershell
    cd C:\path\to\your\scripts
    ```
4.  **Run the Script:** Execute the script using:
    ```powershell
    .\postgres_owner_transfer.ps1
    ```
5.  **Execution Policy (If Necessary):** If you encounter an error about scripts being disabled, you may need to adjust the execution policy for the current PowerShell session. You can bypass it for this session using:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process -Force
    # Then run the script again:
    .\postgres_owner_transfer.ps1
    ```
6.  **Follow Prompts:** The script will guide you through the process by asking a series of questions.

## Script Prompts and How to Answer

The script will ask the following questions interactively:

1.  **Host (default: localhost):**
    * **Question:** Enter the hostname or IP address of your PostgreSQL server.
    * **Answer:** Type the hostname (e.g., `db.example.com`) or IP address (e.g., `192.168.1.100`). Press Enter to accept the default `localhost` if the server is on the same machine.
2.  **Port (default: 5432):**
    * **Question:** Enter the port number PostgreSQL is listening on.
    * **Answer:** Type the port number (e.g., `5433`). Press Enter to accept the default `5432`. Input must be a number between 1 and 65535.
3.  **Username:**
    * **Question:** Enter the PostgreSQL username to connect with (this user needs sufficient permissions).
    * **Answer:** Type the username (e.g., `postgres` or `admin_user`). Cannot be empty. Must contain only letters, numbers, and underscores.
4.  **Password:**
    * **Question:** Enter the password for the specified PostgreSQL username.
    * **Answer:** Type the password. Input will be hidden for security. Cannot be empty.
    * *(The script will test the connection. If it fails, it will loop back and ask for credentials again.)*
5.  **Enter the username whose ownership details you want to view:**
    * **Question:** After listing available users, specify which user's table ownership you want to examine.
    * **Answer:** Type the exact username from the list provided (e.g., `old_app_user`). The script validates that the user exists.
6.  **Do you want to view ownership for all databases (0) or a specific database (1)?:**
    * **Question:** Choose whether to scan all databases or narrow down to one.
    * **Answer:** Enter `0` to check all databases listed earlier, or `1` to select a specific database.
7.  **(If 1 chosen above) Enter the number of the database you want to view:**
    * **Question:** The script lists databases where the target user owns at least one table, assigning a number to each. Enter the number corresponding to the database you want to focus on.
    * **Answer:** Enter the number from the list (e.g., `2`).
8.  **(If a specific database was chosen) Do you want to view ownership for all schemas (0) or specific schemas (1)?:**
    * **Question:** Within the chosen database, choose whether to scan all schemas or narrow down further.
    * **Answer:** Enter `0` to check all schemas in that database, or `1` to select specific schemas.
9.  **(If 1 chosen above) Enter the schema numbers you want to view (comma-separated):**
    * **Question:** The script lists schemas within the selected database where the target user owns tables, assigning a number to each. Enter the numbers for the schemas you want to focus on.
    * **Answer:** Enter one or more numbers separated by commas (e.g., `1` or `1,3,4`).
    * *(The script then displays a numbered list of tables owned by the target user based on your database/schema selections.)*
10. **Would you like to transfer ownership from '[targetUser]'? (1/0):**
    * **Question:** Confirm if you want to proceed with transferring ownership of the listed tables.
    * **Answer:** Enter `1` for Yes or `0` for No. If 0, the script ends.
11. **(If 1 chosen above) Please enter the username you want to transfer ownership to:**
    * **Question:** Specify the existing user who should become the new owner of the tables.
    * **Answer:** Type the exact username from the list of users displayed earlier (e.g., `new_app_owner`). The script validates that the user exists.
12. **(If 1 chosen above) Select option (1 or 2):**
    * **Question:** Choose the transfer scope:
        * `1. Transfer ownership of specific table or table's`
        * `2. Transfer all ownerships of '[targetUser]' to '[newOwner]'`
    * **Answer:** Enter `1` to select specific tables by number, or `2` to transfer all tables listed in the ownership results table.
13. **(If 1 chosen above) Please enter the table numbers to transfer, separated by commas (e.g., 1, 2, 3):**
    * **Question:** Based on the numbered table of ownership results displayed earlier, enter the numbers corresponding to the specific tables you want to transfer.
    * **Answer:** Enter one or more numbers separated by commas (e.g., `1` or `5, 8, 12`). The script validates that the numbers correspond to valid entries in the list.
    * *(The script then executes the `ALTER TABLE ... OWNER TO ...` commands for the selected tables or all tables, reporting success or failure for each.)*

## Conclusion

This script automates the potentially tedious process of identifying and transferring table ownership within a PostgreSQL environment. By providing an interactive, guided workflow with validation, it helps reduce manual errors when performing these administrative tasks. Remember to use it cautiously, especially in production environments.

## Disclaimer

Modifying database object ownership is a significant administrative action.

* **Backup:** Always ensure you have reliable backups of your databases before running scripts that modify ownership or other schema elements.
* **Test:** Test this script thoroughly in a non-production environment that mirrors your production setup before using it on live data.
* **Permissions:** Understand the permissions required and the implications of changing ownership. The new owner will need appropriate permissions to manage the tables.
* **Use at Your Own Risk:** The authors or providers of this script are not responsible for any data loss or issues caused by its use.