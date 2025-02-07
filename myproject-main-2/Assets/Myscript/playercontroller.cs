using UnityEngine;

public class playercontroller : MonoBehaviour

{public float speed = 5.0f;
private Rigidbody rb;
public float rotationSpeed = 120f;
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {

    
    }


    // Update is called once per frame
    void Update()
    {
        rb = GetComponent<Rigidbody>();


    }

        private void FixedUpdate(){
        float moveVertical = Input.GetAxis("Vertical"); 
        Vector3 movement = transform.forward * moveVertical * speed * Time.fixedDeltaTime; 
        rb.MovePosition(rb.position + movement); 

        float turn = Input.GetAxis("Horizontal") * rotationSpeed * Time.fixedDeltaTime; 
        Quaternion turnRotation = Quaternion.Euler(0f, turn, 0f); 
        rb.MoveRotation(rb.rotation * turnRotation); 
    }
    
}
