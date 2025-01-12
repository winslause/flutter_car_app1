from flask import Flask, jsonify, request
from flask_mysqldb import MySQL
from flask_cors import CORS
import os

app = Flask(__name__)
CORS(app)  # Enable CORS for cross-origin access

# Use environment variables for sensitive information
app.config['MYSQL_HOST'] = os.getenv('MYSQL_HOST', 'localhost')
app.config['MYSQL_USER'] = os.getenv('MYSQL_USER', 'root')
app.config['MYSQL_PASSWORD'] = os.getenv('MYSQL_PASSWORD', '')
app.config['MYSQL_DB'] = os.getenv('MYSQL_DB', 'potholes')

mysql = MySQL(app)

@app.route('/')
def index():
    return "Welcome to the Pothole Coordinates API. Use /coordinates to get or add data."

@app.route('/coordinates', methods=['GET'])
def get_coordinates():
    try:
        # Log that the request was received
        print("Request received at /coordinates")

        # Attempt to query the database
        with mysql.connection.cursor() as cur:
            print("Executing query...")
            cur.execute("SELECT type, latitude, longitude FROM locations")
            data = cur.fetchall()
        
        # Print raw data fetched from DB
        print("Raw Data from DB:", data)
        
        # Format the data and print it before returning
        formatted_data = [{'type': row[0], 'latitude': row[1], 'longitude': row[2]} for row in data]
        print("Formatted Data:", formatted_data)
        
        return jsonify(formatted_data)
    except Exception as e:
        # Print any error to the console
        print(f"An error occurred: {str(e)}")
        return jsonify({"error": "An error occurred while fetching coordinates."}), 500

@app.route('/coordinates', methods=['POST'])
def add_coordinates():
    try:
        # Extract JSON data from the request
        data = request.json
        if not data or 'type' not in data or 'latitude' not in data or 'longitude' not in data:
            return jsonify({"error": "Missing required fields in the request."}), 400

        type = data['type']
        latitude = data['latitude']
        longitude = data['longitude']

        # Insert the new coordinate into the database
        with mysql.connection.cursor() as cur:
            # Note: This assumes you have a 'locations' table with columns 'type', 'latitude', and 'longitude'
            cur.execute("INSERT INTO locations (type, latitude, longitude) VALUES (%s, %s, %s)", 
                        (type, latitude, longitude))
            mysql.connection.commit()  # Commit the changes to the database

        # Log the insertion
        print(f"Inserted new coordinate: {type}, {latitude}, {longitude}")
        
        return jsonify({"message": "Coordinate successfully added."}), 201
    
    except Exception as e:
        # Log any errors
        print(f"An error occurred while adding coordinate: {str(e)}")
        return jsonify({"error": "An error occurred while adding the coordinate."}), 500

if __name__ == '__main__':
    app.run(debug=True)  # Set debug=False in production