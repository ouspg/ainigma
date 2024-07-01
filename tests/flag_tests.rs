#[cfg(test)]
mod tests {        
    use autograder::flag_generator::{compare_hmac, generate_flag32, generate_hmac, generate_userseed, generate_uuid};
    use uuid::Uuid;
    #[test]
    fn test_new() {
        assert!(generate_uuid().is_ok());
    }
    #[test]
    fn test_compare_hmac() {
        let id = Uuid::now_v7();
        let secret = "Work".to_string();
        let taskid = "task1".to_string();
        let secret2 = "Work".to_string();
        let taskid2 = "task1".to_string();
        let hash = generate_hmac(id, secret, taskid).expect("error");
        print!("{}", hash);
        assert!(compare_hmac(hash, id, secret2, taskid2).expect("should work"))
    }

    #[test]
    fn test_rand() {
        assert!(generate_flag32().is_ok());
    }
    #[test]
    fn test_userseed(){
        let id1 = Uuid::now_v7();
        let id2 = Uuid::now_v7();
        assert!(generate_userseed(id1).is_ok());

        assert!(generate_userseed(id1).expect("no error") != generate_userseed(id2).expect("no error"));
    }
}
