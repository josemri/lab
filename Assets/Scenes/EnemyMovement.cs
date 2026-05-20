using UnityEngine;

public class EnemyMovement : MonoBehaviour
{
    public Transform target;
    public float speed = 5f;
    public float hitDistance = 1.5f;

    void Update()
    {
        if (target == null) return;

        Vector3 dir = (target.position - transform.position).normalized;
        transform.position += dir * speed * Time.deltaTime;

        transform.LookAt(target);

        float distance = Vector3.Distance(transform.position, target.position);

        if (distance <= hitDistance)
        {
            OnHitPlayer();
        }
    }

    void OnHitPlayer()
    {
        FindObjectOfType<GameManager>().DamagePlayer();
        Destroy(gameObject);
    }
}