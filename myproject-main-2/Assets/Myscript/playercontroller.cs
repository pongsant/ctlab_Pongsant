using UnityEngine;

public class playercontroller : MonoBehaviour
{
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        public float speed = 5.0f;
        private
    }

    // Update is called once per frame
    void Update()
    {
        rb = GetComponent<Rigidbody>();
        void Start()
    }

    private void FixedUpdate(){
        //getting keyboard input andstrin in variable
        float moveVertical = Input.GetAxxis("Vertical");
        Vector3 movement = transform.forward * moveVertical * speed * Time.fixedDeltaTime;
       // Debug.Log(movement);
       rb.MovePosition(rb.MovePosition)
    }
}
