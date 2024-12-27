resource "aws_launch_template" "web" {
  name_prefix   = "${var.environment}-template"
  image_id      = "ami-0735c191cf914754d"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [aws_security_group.web.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysql mysql
              systemctl start httpd
              systemctl enable httpd
              
              # Install AWS CLI for S3 logging
              yum install -y aws-cli

              # Create web application
              cat <<'EOT' > /var/www/html/index.php
              <?php
              $servername = "${aws_db_instance.main.endpoint}";
              $username = "${var.db_username}";
              $password = "${var.db_password}";
              $dbname = "appdb";

              $conn = new mysqli($servername, $username, $password, $dbname);

              if ($conn->connect_error) {
                  die("Connection failed: " . $conn->connect_error);
              }

              if ($_SERVER["REQUEST_METHOD"] == "POST") {
                  $name = $_POST['name'];
                  $email = $_POST['email'];
                  
                  $sql = "INSERT INTO users (name, email) VALUES ('$name', '$email')";
                  $conn->query($sql);
              }

              echo "<h1>Web Application</h1>";
              echo "<form method='post'>";
              echo "Name: <input type='text' name='name'><br>";
              echo "Email: <input type='email' name='email'><br>";
              echo "<input type='submit' value='Submit'>";
              echo "</form>";

              $sql = "SELECT * FROM users";
              $result = $conn->query($sql);

              if ($result->num_rows > 0) {
                  echo "<h2>Users:</h2>";
                  while($row = $result->fetch_assoc()) {
                      echo "Name: " . $row["name"]. " - Email: " . $row["email"]. "<br>";
                  }
              }
              ?>
              EOT

              # Set up logging to S3
              echo '*/5 * * * * aws s3 cp /var/log/httpd/access_log s3://${aws_s3_bucket.logs.id}/logs/$(date +\%Y-\%m-\%d)/access_log' > /etc/cron.d/logs
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-web"
      Environment = var.environment
    }
  }
}